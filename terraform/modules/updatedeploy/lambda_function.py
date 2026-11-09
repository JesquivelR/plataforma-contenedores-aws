import os
import boto3
import json

ecs_client = boto3.client('ecs')

def lambda_handler(event, context):
    ecs_cluster = os.environ['ECS_CLUSTER']
    taskRoleArn = os.environ['TASK_ROLE']
    executionRoleArn = os.environ['EXECUTION_ROLE']
    environment = os.environ['ENVIRONMENT']
    repositorio_ecr = os.environ['REPOSITORIO_ECR']

    try:
        # Extraer información del evento
        detail = event['detail']
        repository_name = detail['repository-name'] 
        image_tag = detail['image-tag'] 


        app_name = repository_name.split('/')[-1]
        service_name = f"{environment}-{app_name}-service"
        image_uri = f"{repositorio_ecr}/{detail['repository-name']}:{image_tag}"

        print(f"Procesando push en repositorio: {repository_name}")
        print(f"Servicio objetivo: {service_name}")
        print(f"Imagen: {image_uri}")

        # Verificar si el servicio existe en el clúster
        response = ecs_client.list_services(cluster=ecs_cluster)
        service_names = [arn.split('/')[-1] for arn in response['serviceArns']]
        print(f"Servicio encontrados: {service_names}")

        if service_name in service_names:
            print(f"Actualizando servicio existente: {service_name}")

            container_definition = {
                'name': app_name,
                'image': image_uri,
                'essential': True,
                'readonlyRootFilesystem': True,
                'portMappings': [
                    {
                        'containerPort': 8000,
                        'protocol': 'tcp'
                    }
                ]
            }

            task_definition_name = f"{environment}-{app_name}-task"

            task_definition_response = ecs_client.register_task_definition(
                family=task_definition_name,
                containerDefinitions=[container_definition],
                networkMode='awsvpc',
                taskRoleArn=taskRoleArn,
                executionRoleArn=executionRoleArn,
                requiresCompatibilities=['FARGATE'],
                cpu='1024',
                memory="3072",
                runtimePlatform={
                    'cpuArchitecture': 'X86_64',
                    'operatingSystemFamily': 'LINUX'
                }
            )
            task_definition_arn = task_definition_response['taskDefinition']['taskDefinitionArn']
            print(f"Task definition registrada exitosamente: {task_definition_arn}")

            update_response = ecs_client.update_service(
                cluster=ecs_cluster,
                service=service_name,
                taskDefinition=task_definition_arn,
                desiredCount=2
            )
            print(f"Servicio {service_name} actualizado exitosamente con la nueva task definition.")
        else:
            print(f"Servicio {service_name} no encontrado en el clúster {ecs_cluster}. No se realizaron cambios.")

    except ecs_client.exceptions.ServiceNotFoundException:
        print(f"ERROR: Servicio {service_name} no se encuentra en el clúster.")
    except Exception as e:
        print(f"ERROR inesperado: {str(e)}")