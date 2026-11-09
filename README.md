# Plataforma de contenedores en AWS

## Objetivo

Infraestructura como código para desplegar aplicaciones en contenedores sobre AWS con alta disponibilidad: dos servicios en ECS Fargate detrás de un Application Load Balancer, red con subredes públicas y privadas, y una función Lambda que actualiza los servicios cuando se publica una imagen nueva en ECR. Todo se define con Terraform y se despliega desde GitHub Actions, que se autentica en AWS con OIDC y no guarda llaves de acceso.

## Arquitectura

![Arquitectura](./images/Arquitectura_Propuesta.jpg)

Flujo general:

1. El workflow `Build and Push to ECR` construye las imágenes de `app1` y `app2` y las publica en ECR.
2. EventBridge detecta el push a ECR e invoca una función Lambda.
3. La Lambda actualiza los servicios de ECS para que usen la imagen nueva.
4. El ALB, ubicado en subredes públicas, reparte el tráfico HTTP hacia las tareas Fargate que corren en subredes privadas.
5. Las tareas salen a Internet únicamente a través del NAT Gateway.

Las decisiones de diseño están en [design.md](./design.md).

## Componentes

| Componente | Descripción |
|---|---|
| VPC | Red con subredes públicas y privadas en dos zonas de disponibilidad, Internet Gateway y NAT Gateway |
| ALB | Balanceador de aplicaciones con grupos de destino y reglas por ruta hacia cada servicio |
| ECS Fargate | Clúster, definiciones de tarea y servicios de `app1` y `app2` |
| ECR | Repositorios de imágenes de ambas aplicaciones |
| Lambda y EventBridge | Actualizan los servicios de ECS cuando llega una imagen nueva |
| IAM | Roles de ejecución y de tarea de ECS, rol de la Lambda y rol OIDC para GitHub Actions |
| S3 y DynamoDB | Estado remoto de Terraform y bloqueo |

## Estructura del repositorio

```text
.
├── app1/                  Aplicación 1 (Dockerfile, main.py, requirements.txt)
├── app2/                  Aplicación 2
├── images/                Capturas y diagrama
├── design.md              Decisiones de diseño
├── .github/workflows/     CI de Terraform, build de imágenes y despliegues
└── terraform/
    ├── global/            Proveedor OIDC de GitHub y rol IAM de los workflows
    ├── environments/      Entornos dev y stage
    └── modules/           vpc, alb, ecs, iam y updatedeploy
```

## Autenticación de CI/CD con OIDC

Los workflows no usan `AWS_ACCESS_KEY_ID` ni `AWS_SECRET_ACCESS_KEY`. Cada ejecución pide un token a GitHub (`permissions: id-token: write`) y AWS lo cambia por credenciales temporales con `AssumeRoleWithWebIdentity`.

```text
GitHub Actions --token OIDC--> AWS STS --valida trust policy--> credenciales temporales --> rol IAM
```

La trust policy, definida en `terraform/global/oidc.tf`, exige que:

- `aud` sea `sts.amazonaws.com`;
- `sub` sea `repo:JesquivelR/plataforma-contenedores-aws:ref:refs/heads/main` o uno de los entornos declarados (`dev`, `stage`).

Cualquier otro repositorio o rama no puede asumir el rol. Si cambias el nombre del repositorio o la rama, ajusta las variables `github_owner`, `github_repo` y `github_branch`.

El pipeline `CI de Terraform` corre en cada PR con `terraform fmt -check`, `validate`, tflint y Checkov, sin credenciales de AWS.

## Requisitos

- Cuenta de AWS con permisos para crear los recursos anteriores.
- Terraform 1.10 o superior y AWS CLI configurado para el paso inicial.
- Cuenta de GitHub y git.

## Despliegue

1. **Clonar el repositorio**

   ```bash
   git clone https://github.com/JesquivelR/plataforma-contenedores-aws.git
   cd plataforma-contenedores-aws
   ```

2. **Crear el proveedor OIDC y el rol (una sola vez, desde tu equipo)**

   Este paso necesita credenciales propias porque el rol todavía no existe.

   ```bash
   cd terraform/global
   terraform init
   terraform apply
   terraform output github_actions_role_arn
   ```

   Si tu cuenta ya tiene el proveedor OIDC de GitHub, impórtalo antes de aplicar o ajusta `oidc.tf`, porque AWS permite uno solo por URL.

3. **Configurar los secretos del repositorio** en `Settings > Secrets and variables > Actions`:

   | Secreto | Valor |
   |---|---|
   | `AWS_ROLE_ARN` | Salida `github_actions_role_arn` del paso anterior |
   | `AWS_REGION` | `us-west-1` |
   | `TF_S3_BUCKET` | Nombre del bucket de estado, único a nivel global |
   | `TF_S3_KEY` | `infra.tfstate` |
   | `TF_DYNAMODB_TABLE` | `terraform-lock-table` |
   | `ECR_REGISTRY` | URI del registro de ECR, disponible después del primer workflow |

4. **Ejecutar los workflows en este orden** (`Actions > workflow > Run workflow`):

   1. `Crear Infraestructura Previa`: crea el bucket de estado, la tabla de bloqueo y los repositorios de ECR. Se ejecuta una vez. Luego configura `ECR_REGISTRY`.
   2. `Build and Push to ECR`: construye y publica las imágenes. Puede repetirse cada vez que cambie el código de las aplicaciones.
   3. `Despliegue o Destrucción de Infraestructura - Dev` (o `Stage`): despliega la red, el ALB, ECS y la Lambda.

   ![Workflows disponibles](./images/View_workflows.png)

5. **Probar**

   Al terminar el despliegue, obtén el DNS del ALB en la consola de EC2, en `Balanceadores de carga`, o con `terraform output`. El ALB escucha en HTTP:

   ```bash
   curl http://<dns-del-alb>
   ```

   ![Respuesta de la aplicación](./images/Response2.png)

   Para ver un cambio, modifica [app1/main.py](./app1/main.py), vuelve a ejecutar `Build and Push to ECR` y consulta de nuevo la URL.

## Costos aproximados

Referencia para `us-west-1`, con el entorno encendido de forma continua. Los precios cambian: verifica en la calculadora de AWS.

| Recurso | Aproximado mensual |
|---|---|
| NAT Gateway | 35 a 40 USD más datos procesados |
| Application Load Balancer | 18 a 20 USD más LCU |
| Fargate (dos servicios pequeños) | 15 a 30 USD según tamaño y réplicas |
| ECR, S3, DynamoDB, Lambda, EventBridge | menos de 5 USD con poco uso |

El NAT Gateway y el ALB son la mayor parte del gasto. Destruye el entorno cuando no lo uses.

## Limpieza

Para eliminar la infraestructura, cambia `DESTROY_INFRA` a `True` en [deploy-IaC-dev.yml](.github/workflows/deploy-IaC-dev.yml), haz push y ejecuta el workflow de despliegue de dev. Después, elimina desde `terraform/global` el rol OIDC con `terraform destroy` si ya no lo necesitas, y vacía y borra manualmente el bucket de estado, la tabla de DynamoDB y los repositorios de ECR.

---

# Documentación de configuración en Terraform

# Documentación del Archivo `main.tf` - Configuración de VPC

Este archivo define los recursos necesarios para implementar una VPC con subredes públicas y privadas, un gateway NAT e internet gateway. Está diseñado para entornos escalables y seguros.

---

## **1. Creación de la VPC**

### Recurso: `aws_vpc.this`
- **Descripción:** Crea una VPC con el bloque CIDR especificado.
- **Configuración Clave:**
  - **CIDR:** Se define en la variable `var.cidr`.
  - **Etiquetas:** Asigna un nombre basado en el entorno (`${var.environment}-vpc`).

---

## **2. Subredes Públicas**

### Recurso: `aws_subnet.public`
- **Descripción:** Crea subredes públicas dentro de la VPC.
- **Configuración Clave:**
  - **Cantidad:** Determinada por la longitud de `var.public_subnets`.
  - **CIDR:** Cada subred utiliza los valores en `var.public_subnets`.
  - **Zona de Disponibilidad:** Definida en `var.availability_zones`.
  - **IP Pública:** Habilitada con `map_public_ip_on_launch = true`.
  - **Etiquetas:** Nombres en el formato `${var.environment}-public-subnet-{index}`.

---

## **3. Subredes Privadas**

### Recurso: `aws_subnet.private`
- **Descripción:** Crea subredes privadas dentro de la VPC.
- **Configuración Clave:**
  - **Cantidad:** Determinada por la longitud de `var.private_subnets`.
  - **CIDR:** Utiliza los valores en `var.private_subnets`.
  - **Zona de Disponibilidad:** Configurada con `var.availability_zones`.
  - **Etiquetas:** Nombres en el formato `${var.environment}-private-subnet-{index}`.

---

## **4. Internet Gateway**

### Recurso: `aws_internet_gateway.this`
- **Descripción:** Permite que las subredes públicas tengan acceso a internet.
- **Configuración Clave:**
  - **VPC Asociada:** La VPC creada en `aws_vpc.this`.
  - **Etiquetas:** Nombre en el formato `${var.environment}-internet-gateway`.

---

## **5. Tabla de Rutas Públicas**

### Recurso: `aws_route_table.public`
- **Descripción:** Configura una tabla de rutas para las subredes públicas.
- **Configuración Clave:**
  - **VPC Asociada:** `aws_vpc.this`.
  - **Ruta por Defecto:**
    - **Destino:** `0.0.0.0/0` (todo el tráfico externo).
    - **Gateway:** `aws_internet_gateway.this.id`.
  - **Etiquetas:** Nombre en el formato `${var.environment}-public-route-table`.

### Asociación de Tabla de Rutas
- **Recurso:** `aws_route_table_association.public`
- **Descripción:** Asocia la tabla de rutas públicas con cada subred pública.

---

## **6. NAT Gateway**

### Recurso: `aws_nat_gateway.this`
- **Descripción:** Permite que las subredes privadas accedan a internet para tareas como actualizaciones de paquetes.
- **Configuración Clave:**
  - **Elastic IP:** Asignado mediante `aws_eip.nat.id`.
  - **Subred:** Implementado en la primera subred pública (`aws_subnet.public[0]`).
  - **Etiquetas:** Nombre en el formato `${var.environment}-nat-gateway`.

---

## **7. Elastic IP para NAT**

### Recurso: `aws_eip.nat`
- **Descripción:** Proporciona una dirección IP estática para el NAT Gateway.
- **Configuración Clave:**
  - **Dependencia:** Creado después del Internet Gateway (`depends_on = [aws_internet_gateway.this]`).

---

## **8. Tabla de Rutas Privadas**

### Recurso: `aws_route_table.private`
- **Descripción:** Configura una tabla de rutas para las subredes privadas.
- **Configuración Clave:**
  - **VPC Asociada:** `aws_vpc.this`.
  - **Ruta por Defecto:**
    - **Destino:** `0.0.0.0/0`.
    - **Gateway NAT:** `aws_nat_gateway.this.id`.
  - **Etiquetas:** Nombre en el formato `${var.environment}-private-route-table`.

### Asociación de Tabla de Rutas
- **Recurso:** `aws_route_table_association.private`
- **Descripción:** Asocia la tabla de rutas privadas con cada subred privada.

---

# Resumen
Este archivo implementa:
1. Una **VPC** con subredes públicas y privadas.
2. Un **Internet Gateway** para las subredes públicas.
3. Un **NAT Gateway** para proporcionar conectividad a internet desde subredes privadas.
4. Tablas de rutas públicas y privadas para gestionar el flujo de tráfico.

Esta configuración es útil para arquitecturas donde las instancias en subredes privadas necesitan acceso a internet sin ser accesibles directamente desde el exterior.


# Documentación del Archivo `main.tf` - Configuración de IAM

Este archivo define roles y políticas IAM necesarios para habilitar la ejecución de tareas ECS. A continuación, se explica cada recurso configurado.

---

## **1. Rol de Ejecución para ECS**

### Recurso: `aws_iam_role.ecs_execution`
- **Descripción:** Crea un rol que será asumido por tareas ECS para acceder a servicios de AWS como ECR y CloudWatch.
- **Configuración Clave:**
  - **Nombre:** `${var.environment}-ecs-execution-role` (incluye el entorno).
  - **Política de Asunción:** Permite que el servicio `ecs-tasks.amazonaws.com` asuma este rol.
  - **Ejemplo de Política:**
    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": { "Service": "ecs-tasks.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }
      ]
    }
    ```

---

## **2. Adjuntar Política Administrada al Rol de Ejecución**

### Recurso: `aws_iam_role_policy_attachment.ecs_execution_policy`
- **Descripción:** Vincula la política administrada de AWS `AmazonECSTaskExecutionRolePolicy` al rol de ejecución para permitir:
  - Recuperar imágenes desde ECR.
  - Registrar logs en CloudWatch.
- **Configuración Clave:**
  - **Policy ARN:** `arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy`.

---

## **3. Política en Línea para el Rol de Ejecución**

### Recurso: `aws_iam_role_policy.ecs_execution_policy_inline`
- **Descripción:** Define permisos adicionales para que las tareas ECS puedan crear grupos de logs en CloudWatch.
- **Configuración Clave:**
  - **Nombre:** `${var.environment}-ecs-execution-policy-inline`.
  - **Acción Permitida:** `logs:CreateLogGroup`.
  - **Recursos Permitidos:** `arn:aws:logs:*:*:*` (todos los grupos de logs).

---

## **4. Rol para las Tareas de ECS**

### Recurso: `aws_iam_role.ecs_task`
- **Descripción:** Crea un rol asumido por las tareas ECS para ejecutar contenedores con permisos personalizados.
- **Configuración Clave:**
  - **Nombre:** `${var.environment}-ecs-task-role`.
  - **Política de Asunción:** Permite que `ecs-tasks.amazonaws.com` asuma este rol.
  - **Ejemplo de Política:**
    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": { "Service": "ecs-tasks.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }
      ]
    }
    ```

---

## **5. Adjuntar Política Administrada al Rol de Tareas**

### Recurso: `aws_iam_role_policy_attachment.ecs_task_policy_attachment`
- **Descripción:** Vincula la política administrada de AWS `AmazonECSTaskExecutionRolePolicy` al rol de tareas ECS, otorgando permisos generales para la ejecución de contenedores.

---

## **6. Política en Línea para las Tareas de ECS**

### Recurso: `aws_iam_role_policy.ecs_task_policy`
- **Descripción:** Adjunta una política personalizada al rol de tareas ECS. 
- **Configuración Clave:**
  - **Nombre:** `${var.environment}-ecs-task-policy`.
  - **Política:** Definida en un archivo externo (`ecs_task_policy.json`), que incluye permisos específicos para la lógica de la aplicación.

---

# Resumen
Este archivo configura los elementos necesarios para que ECS interactúe con los recursos de AWS:
1. **Rol de Ejecución (`ecs_execution`):** Habilita la interacción con ECR y CloudWatch.
2. **Rol de Tareas (`ecs_task`):** Proporciona permisos personalizados para ejecutar tareas ECS.
3. **Políticas Administradas y En Línea:** Combina permisos estándar y específicos para cada ambiente.

---

# Documentación del Archivo `main.tf` - Configuración de ECS


Este archivo `main.tf` configura un clúster de **AWS ECS** utilizando Fargate para desplegar dos aplicaciones (`app1` y `app2`). A continuación, se describe cada componente en detalle.

---

## **1. Clúster de ECS**
Se crea un clúster ECS para alojar las tareas:

```hcl
resource "aws_ecs_cluster" "this" {
  name = "${var.environment}-ecs-cluster"
}
```
## **2. Definiciones de Tarea (Task Definitions)**
Se definen las tareas de ECS para cada aplicación. Las tareas incluyen configuración del contenedor, red, y monitoreo.

#### **Tarea de `app1`**

```hcl
resource "aws_ecs_task_definition" "app1" {
  family                   = "${var.environment}-${var.app1_image}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "3072"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = var.app1_image
      image     = "${var.repositorio_ecr}/${var.app1_image}:${var.image_tag}"
      essential = true
      portMappings = [
        {
          name          = "${var.app1_image}-8000-tcp"
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = [
        {
          name  = "ENV"
          value = var.environment
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.environment}-${var.app1_image}"
          "awslogs-region"        = var.aws_region
          "awslogs-create-group"  = "true"
          "awslogs-stream-prefix" = "ecs"
          "mode"                  = "non-blocking"
          "max-buffer-size"       = "25m"
        }
      }
    }
  ])
}
```
#### **Tarea de `app2`**
```hcl
resource "aws_ecs_task_definition" "app2" {
  family                   = "${var.environment}-${var.app2_image}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = var.app2_image
      image     = "${var.repositorio_ecr}/${var.app2_image}:${var.image_tag}"
      portMappings = [
        {
          name          = "${var.app2_image}-8000-tcp"
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = [
        {
          name  = "ENV"
          value = var.environment
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.environment}-${var.app2_image}"
          "awslogs-region"        = var.aws_region
          "awslogs-create-group"  = "true"
          "awslogs-stream-prefix" = "ecs"
          "mode"                  = "non-blocking"
          "max-buffer-size"       = "25m"
        }
      }
    }
  ])
}
```

## **3. Servicios ECS (ECS Services)**
Cada aplicación se configura como un servicio ECS para asegurar la disponibilidad y administración del ciclo de vida.

#### **Servicio de `app1`**

```hcl
resource "aws_ecs_service" "app1" {
  name            = "${var.environment}-${var.app1_image}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app1.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnets
    security_groups = [var.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.app1_target_group_arn
    container_name   = var.app1_image
    container_port   = 8000
  }
}
```

#### **Servicio de `app2`**

```hcl
resource "aws_ecs_service" "app2" {
  name            = "${var.environment}-${var.app2_image}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app2.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnets
    security_groups = [var.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.app2_target_group_arn
    container_name   = var.app2_image
    container_port   = 8000
  }
}
```
# Resumen
Este archivo implementa:
1. Un **clúster de ECS** para ejecutar las tareas.
2. Define las **tareas ECS** para `app1` y `app2` con sus configuraciones específicas:
   - Recursos como CPU, memoria y roles de ejecución.
   - Definiciones del contenedor, incluyendo puertos, variables de entorno y configuración de logs.
3. Configura los **servicios ECS** para `app1` y `app2`, asegurando alta disponibilidad y conectividad con subredes y balanceadores de carga.

# Documentación del Archivo `main.tf` - Configuración de ALB

Este archivo `main.tf` configura un **Application Load Balancer (ALB)** en AWS para enrutar el tráfico hacia dos aplicaciones (`app1` y `app2`) utilizando Terraform. A continuación, se describen los recursos creados.

---
## 1. Application Load Balancer (ALB)
Se crea un ALB que distribuye tráfico hacia las aplicaciones configuradas.

```hcl
resource "aws_lb" "this" {
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnets

  enable_deletion_protection = false

  tags = {
    Environment = var.environment
  }
}
```
## 2. Grupos de Destino (Target Groups)

**Grupo de destino para ```app1```**
- Define el puerto, protocolo y verificaciones de salud específicas para la primera aplicación.
```hcl
resource "aws_lb_target_group" "app1" {
  name        = "${var.environment}-${var.app1_image}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Environment = var.environment
  }
}
```
**Grupo de destino para ```app2```**
- Similar al grupo de destino de app1, pero con configuración específica para la segunda aplicación.
```hcl
resource "aws_lb_target_group" "app2" {
  name        = "${var.environment}-${var.app2_image}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Environment = var.environment
  }
}
```

## 3. Listeners
Se configuran listeners para enrutar el tráfico HTTP a los grupos de destino.

**Listener para ```app1```**
- Enruta tráfico HTTP en el puerto 80 hacia el grupo de destino de app1.
```hcl
resource "aws_lb_listener" "http-app1" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app1.arn
  }
}

```
**Listener para ```app2```**
- Enruta tráfico HTTP en el puerto 8080 hacia el grupo de destino de app2.
```hcl
resource "aws_lb_listener" "http-app2" {
  load_balancer_arn = aws_lb.this.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app2.arn
  }
}
```
---
# **Resumen**
Este script de Terraform realiza las siguientes configuraciones principales:

1. Crea un **Application Load Balancer** con seguridad y configuración específicas.
2. Define **grupos de destino (Target Groups)** para las aplicaciones:
   - Configuración de los puertos, protocolos y verificaciones de salud.
3. Configura **listeners** que enrutan tráfico HTTP a los grupos de destino correspondientes.

---

# Documentación del Archivo `main.tf` - Actualización de Despliegues con Lambda y ECS

Este archivo define los recursos necesarios para implementar una función Lambda que actualiza servicios ECS al recibir eventos de push en ECR. Está diseñado para ser escalable, eficiente y automatizado.

---

## **1. Roles y Políticas de IAM**

### Recurso: `aws_iam_role.lambda_role`
- **Descripción:** Rol IAM que permite a Lambda asumir permisos necesarios.
- **Configuración Clave:**
  - **Política de Asunción:** Permite que `lambda.amazonaws.com` asuma este rol.
  - **Etiquetas:** Nombre del rol basado en el entorno (`lambda-role-${var.environment}`).

### Recurso: `aws_iam_role_policy_attachment.lambda_policy_attachment`
- **Descripción:** Adjunta la política básica de ejecución para Lambda.
- **Configuración Clave:**
  - **Política:** `AWSLambdaBasicExecutionRole`.

### Recurso: `aws_iam_policy.ecs_permissions`
- **Descripción:** Política personalizada que otorga permisos para interactuar con ECS.
- **Configuración Clave:**
  - **Permisos Incluidos:**
    - `ecs:RegisterTaskDefinition`
    - `ecs:UpdateService`
    - `ecs:DescribeServices`
    - `ecs:DescribeClusters`
    - `ecs:ListServices`
    - `iam:PassRole`
  - **Alcance:** Aplicado a todos los recursos (`Resource = ["*"]`).

### Recurso: `aws_iam_role_policy_attachment.ecs_policy_attachment`
- **Descripción:** Adjunta la política personalizada a la función Lambda.
- **Configuración Clave:**
  - **Rol Asociado:** `lambda-role-${var.environment}`.

---

## **2. Función Lambda**

### Recurso: `aws_lambda_function.update_deploy_lambda`
- **Descripción:** Función Lambda que actualiza los servicios ECS tras un evento de push en ECR.
- **Configuración Clave:**
  - **Nombre:** `update-deploy-${var.environment}`.
  - **Rol Asociado:** `lambda-role-${var.environment}`.
  - **Código Fuente:** `lambda.zip` generado en cada `plan` con el data source `archive_file` a partir de `lambda_function.py` (el zip no se versiona).
  - **Variables de Entorno:**
    - `ECS_CLUSTER`
    - `ENVIRONMENT`
    - `EXECUTION_ROLE`
    - `TASK_ROLE`
    - `REPOSITORIO_ECR`
  - **Etiquetas:** Nombre con el formato `update-deploy-${var.environment}`.

---

## **3. Regla de CloudWatch para Disparadores**

### Recurso: `aws_cloudwatch_event_rule.ecr_push_rule`
- **Descripción:** Configura un disparador basado en eventos de push en repositorios ECR.
- **Configuración Clave:**
  - **Evento:** `ECR Image Action` con acción de tipo `PUSH` y resultado `SUCCESS`.
  - **Filtros Personalizados:**
    - Repositorios: `${var.app1_image}`, `${var.app2_image}`.
    - Etiqueta de Imagen: `${var.image_tag}`.

### Recurso: `aws_cloudwatch_event_target.ecr_push_lambda_target`
- **Descripción:** Asocia la regla de CloudWatch con la función Lambda.
- **Configuración Clave:**
  - **Regla:** `ecr-push-rule-${var.environment}`.
  - **Destino:** ARN de la función Lambda.

---

## **4. Permiso para Lambda desde EventBridge**

### Recurso: `aws_lambda_permission.allow_eventbridge`
- **Descripción:** Permite a EventBridge invocar la función Lambda.
- **Configuración Clave:**
  - **Principal:** `events.amazonaws.com`.
  - **ARN de la Fuente:** Regla de CloudWatch `ecr-push-rule-${var.environment}`.

---

## **5. Datos de Identidad del Llamador**

### Data Source: `aws_caller_identity.current`
- **Descripción:** Obtiene información sobre la cuenta de AWS actual para su uso en configuraciones adicionales.

---

# Resumen

Este archivo implementa:
1. Un **rol IAM** y políticas necesarias para la ejecución de Lambda y la interacción con ECS.
2. Una **función Lambda** que actualiza servicios ECS tras eventos de push en ECR.
3. Configuración de **reglas de CloudWatch** para desencadenar la función Lambda.
4. Permisos explícitos para que EventBridge invoque la función Lambda.

Esta configuración automatiza los despliegues en ECS, asegurando un flujo continuo desde la construcción de imágenes en ECR hasta la actualización de servicios en ECS.


