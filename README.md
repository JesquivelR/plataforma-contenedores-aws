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

## Módulos

| Módulo | Qué crea |
|---|---|
| `vpc` | VPC, subredes públicas y privadas por zona, Internet Gateway, NAT Gateway, tablas de rutas y el security group por defecto sin reglas |
| `iam` | Rol de ejecución y rol de tarea para ECS |
| `ecs` | Clúster con Container Insights, task definitions de las dos APIs y sus servicios en Fargate |
| `alb` | Application Load Balancer, target groups y listeners para app1 (puerto 80) y app2 (puerto 8080) |
| `updatedeploy` | Lambda que registra una task definition nueva y actualiza el servicio cuando llega una imagen a ECR, y la regla de EventBridge que la dispara |

## Controles de seguridad

- Las tareas de ECS corren en subredes privadas y solo aceptan tráfico del ALB en el puerto 8000. Su salida está limitada a HTTPS, que es lo que necesitan para ECR, CloudWatch Logs y las APIs de AWS.
- El ALB solo puede enviar tráfico a la VPC en el puerto de la aplicación y descarta los encabezados HTTP inválidos.
- Las subredes públicas no asignan IP pública a lo que se lance en ellas; ahí solo viven el ALB y el NAT Gateway.
- El security group por defecto de la VPC queda sin reglas.
- Los contenedores corren con el sistema de archivos raíz en solo lectura, también en las task definitions que registra la Lambda.
- La política de la Lambda solo puede actualizar servicios del clúster del entorno y pasar los dos roles de las tareas a `ecs-tasks.amazonaws.com`. `ecs:RegisterTaskDefinition` es la única acción con `Resource = "*"`, porque AWS no admite permisos a nivel de recurso para ella.
- La Lambda usa Python 3.12, tiene trazas de X-Ray y un límite de 2 ejecuciones concurrentes.

## Hallazgos de Checkov omitidos

Checkov corre en cada PR y bloquea el merge si encuentra un hallazgo nuevo. Los siguientes se omiten en el código con `#checkov:skip` y un motivo:

| Check | Recurso | Motivo |
|---|---|---|
| CKV_AWS_260, CKV_AWS_2, CKV_AWS_103, CKV2_AWS_20 | Security group y listeners del ALB | El laboratorio no tiene dominio ni certificado de ACM, así que el ALB publica HTTP. Con un dominio se agrega un listener HTTPS con política TLS 1.2 y la redirección desde HTTP. |
| CKV_AWS_378 | Target groups | El TLS terminaría en el ALB; el tráfico hacia las tareas va por subredes privadas. |
| CKV_AWS_150 | ALB | La protección contra borrado está apagada para poder destruir el entorno con `terraform destroy`. |
| CKV_AWS_91 | ALB | Los access logs necesitan un bucket S3 dedicado. |
| CKV2_AWS_28 | ALB | WAF tiene un costo mensual fijo; en producción se asocia un web ACL. |
| CKV2_AWS_11 | VPC | Flow logs fuera del laboratorio por costo. |
| CKV2_AWS_19 | IP elástica | Está asociada al NAT Gateway, no a una instancia EC2. |
| CKV_AWS_116 | Lambda | EventBridge reintenta la invocación; una DLQ en SQS queda fuera del alcance. |
| CKV_AWS_117 | Lambda | Solo llama a la API de ECS; meterla en la VPC exigiría endpoints o NAT sin mejorar el aislamiento. |
| CKV_AWS_173 | Lambda | Las variables de entorno no tienen secretos, solo nombres y ARN. |
| CKV_AWS_272 | Lambda | La firma de código con AWS Signer queda fuera del laboratorio. |
