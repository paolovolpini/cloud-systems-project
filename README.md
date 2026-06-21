# cloud-systems-project

Il seguente progetto prevede il deployment di una semplice app, un accorciatore di URL, su un'infrastruttura cloud AWS. Nello specifico, l'applicativo è containerizzato e gestito mediante un cluster Kubernetes realizzato con un Auto Scaling Group (AGS) e con un bilanciamento di carico mediante l'impiego di un Network Load Balancer (NLB).

## Struttura della repository

La repository è strutturata nel seguente modo:

```
├── application
│   ├── backend
│   │   ├── Dockerfile
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── frontend
│   │   ├── Dockerfile
│   │   ├── index.html
│   │   └── nginx.conf
│   └── k8s
│       ├── backend-deployment.yaml
│       ├── backend-scaling.yaml
│       ├── backend-service.yaml
│       ├── frontend-deployment.yaml
│       ├── frontend-scaling.yaml
│       ├── frontend-service.yaml
│       ├── ingress.yaml
│       ├── postgres-persistentvolume.yaml
│       ├── postgres-service.yaml
│       └── postgres-statefulset.yaml
├── infrastructure
│   └── opentofu
│       ├── control-plane-userdata.tftpl
│       ├── ecr.tf
│       ├── iam.tf
│       ├── instances.tf
│       ├── nlb.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── sg.tf
│       ├── variables.tf
│       ├── vpc.tf
│       └── worker-userdata.tftpl
```

La cartella `application` include il codice sorgente dell'applicazione e i manifest Kubernetes per deployare l'applicazione sul cluster. La cartella `infrastructure/opentofu` contiene i sorgenti per la creazione dell'infrastruttura cloud:

1. `ecr.tf` permette la creazione del registry delle immagini dei container;
2. `iam.tf` definisce i permessi IAM delle istanze EC2 per pullare le immagini;
3. `instances.tf` include le definizioni dei template delle macchine in AGS, la definizione dell'AGS e la definizione del control plane;
4. `nlb.tf` definisce il Network Load Balancer;
5. `sg.tf` definisce il Security Group del cluster;
6. `vpc.tf` definisce la VPC, le sottoreti e il NAT Gateway;
7. `variables.tf` permette la definizione della regione AWS, il tipo di macchine, il numero minimo e massimo di istanze di AGS e l'AMI delle istanze.

## Workflows

La repository include anche tre workflow:

1. `app-cicd.yaml` crea le immagini docker dai sorgenti, caricandole nell'ECR e deployando l'applicazione sul cluster;
2. `infra.yaml` applica le decisioni infrastrutturali definite nella cartella `infrastructure/opentofu`;
3. `destroy.yaml` distrugge tutta l'infrastruttura.

## Protezione 

Il branch `main` è protetto, e i push diretti non sono ammessi. Inoltre, i workflow infrastrutturali (`infra.yaml` e `destroy.yaml`) richiedono l'approvazione esplicita di reviewer.