# Relazione progetto Sistemi Cloud

Il seguente documento illustra la struttura e il funzionamento dell'infrastruttura cloud realizzata su Amazon Web Services (da ora abbreviato AWS) come progetto finale. La relazione seguirà la seguente struttura:

- descrizione dell'infrastruttura;
- spiegazione del processo necessario per la realizzazione dell'infrastruttura;
- analisi del codice sorgente.

## Descrizione dell'infrastruttura

Obiettivo del progetto è la realizzazione di un'infrastruttura cloud usando AWS. L'infrastruttura ospiterà un'applicazione web eseguita un cluster Kubernetes e supporterà meccanismi per garantire continuità operativa. Lo schema a seguire offre una rappresentazione visiva di quanto sarà discusso in sezione:

![schema](./Progetto%20Cloud.drawio.png)

L'infrastruttura realizzata prevede una Virtual Private Network (da ora abbreviata VPC) con sottoreti private e pubbliche distribuite su due Availability Zone (da ora abbreviato AZ). Nello specifico, per ogni AZ è presente una sottorete privata e una sottorete pubblica:

- la sottorete privata ospita i nodi *worker*, ossia i nodi del cluster Kubernetes che eseguiranno i Pod destinati ad ospitare i microservizi dell'applicazione in esecuzione sull'infrastruttura;
- la sotterete pubblica ospita i nodi del NLB. L'utilizzo di due sottoreti pubbliche per il NLB evita che il bilanciatore di carico funga da Single Point of Failure.

All'interno di una delle sottoreti private è ospitato anche il *control-plane*, impiegato per gestire le risorse del cluster.

Le tabelle di *routing* delle sottoreti private presentano una *route* verso Internet mediante un NAT Gateway, presente in una delle sottoreti pubbliche. Questo impedisce ad host esterni di poter raggiungere direttamente i nodi nelle sottoreti private, permettendo comunque a questi di poter recuperare le immagini necessarie per l'esecuzione dei Pod Kubernetes. La VPC è dotata di un Internet Gateway per far sì che i nodi del NLB possano ricevere il traffico da Internet. Infine, il NAT Gateway presenta un Elastic IP, requisito necessario per i seguenti punti:

1. avere un'identità pubblica stabile per le *route* delle sottoreti private;
2. far sì che AWS possa gestire il failover delle istanze di NAT Gateway. Elastic IP è utilizzato per mascherare il fallimento delle istanze associando un IP statico fisso a più istanze.

Le istanze *worker* sono generate mediante un Auto Scaling Group (da ora abbreviato ASG), distribuito su due AZ. Un'opportuna politica di misurazione della CPU permette di scalare dinamicamente i nodi del *worker* in virtù delle condizioni di traffico. Le immagini per l'esecuzione dei microservizi sui nodi *worker* all'interno del cluster Kubernetes sono ospitate mediante il servizio Elastic Container Registry (da ora abbreviato ECR), che fornisce un registro di container Docker gestito da AWS.

Infine, una *repository* Github viene utilizzata per il mantenimento delle immagini e dell'infrastruttura cloud mediante opportuni workflow.

## Realizzare l'infrastruttura

Nella seguente sezione sono descritti i passi necessari per replicare l'infrastruttura Cloud proposta.

### Creazione del ruolo 

Al fine di poter fornire le autorizzazioni necessarie per la *repository* Github, è necessario:

1. aggiungere Github come OpenID Connect Identity Provide;
2. creare un ruolo IAM nell'account AWS.

Per il punto $1.$ è necessario andare nella Console IAM, definendo:

- "OpenID Connect" come tipo di provider;
- `https://token.actions.githubusercontent.com` come URL del provider;
- `sts.amazonaws.com` come audience.

Per il punto $2.$, è necessario creare un ruolo IAM sempre dall'apposita Console, definendo:

- "Identità web" come tipo di entità attendibile, specificando come provider di identità e audience i parametri precedentemente specificati;
- le autorizzazioni necessarie per operare con ECR, S3, SSM, NLB, IAM, EC2 e DynamoDB. Per semplificare il set di policy, è possibile associare il set di policy `AmazonDynamoDBFullAccess`, `AmazonEC2FullAccess`, `AmazonS3FullAccess`, `AmazonSSMFullAccess`, `ElasticLoadBalancingFullAccess`, `IAMFullAccess`, `AmazonEC2ContainerRegistryFullAccess`.

Creato il ruolo, è necessario salvare l'ARN (Amazon Resource Name).

### Fork della repository

Memorizzato l'ARN, è possibile creare un *fork* della *repository*. È necessario configurare due segreti per le Github Actions:

- `ARN_ROLE`, che contiene l'ARN del ruolo IAM di AWS precedentemente creato;
- `POSTGRE_SECRET`, una stringa contenente la password che verrà utilizzata per l'inizializzazione del database PostgreSQL.

La repository forkata **non** avrà le GitHub Actions attivate. È necessario andare sul pannello Actions e attivarle esplicitamente.

Infine, è necessario impostare correttamente il nome del bucket S3 utilizzato per la memorizzazione dello stato OpenTofu `terraform.tfstate`, modificando l'attributo `bucket` del backend `s3` presente nel sorgente `providers.tf` con il nome del bucket creato nell'account. Poiché OpenTofu richiede anche una tabella DynamoDB per lo *state locking*, è necessario creare anche questa con i seguenti requisiti:

- il nome della tabella è `tofu-state-lock`;
- l'attributo della tabella è `LockID`, di tipo stringa e chiave della tabella.
 
È possibile creare il bucket e la tabella DynamoDB utilizzando i comandi CLI:

```sh
aws s3api create-bucket \
  --bucket "<nome bucket>" \
  --region "<nome regione" \
  --create-bucket-configuration LocationConstraint="$AWS_DEFAULT_REGION"

aws s3api put-bucket-versioning \
  --bucket "<nome bucket>" \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name tofu-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

In alternativa, con un sorgente locale OpenTofu simile a quello sottostante:

```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-south-1"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "s3-bucket-pablo-cloud-system"
  force_destroy = true
  tags = { Name = "Pablo bucket for tfstate" }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "tofu-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Name = "tofu-state-lock" }
}
```

I blocchi `aws_s3_bucket_server_side_encryption_configuration` e `aws_s3_bucket_public_access_block` sono necessari per garantire maggiore sicurezza, solitamente inclusa di default nei comandi di AWS CLI. Necessario per l'esecuzione dei comandi è la configurazione del profilo su AWS CLI.

A questo punto, la repository può essere utilizzata per la gestione dell'infrastruttura.

## Analisi dei sorgenti

La seguente sezione propone un'analisi dettagliata dei sorgenti infrastrutturali.

### `providers.tf`

```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "s3-bucket-pablo-cloud-system"
    key    = "k8s/terraform.tfstate"
    region = "eu-south-1"
  }
}

provider "aws" {
  region = "eu-south-1"
}
```

Il file configura il provider AWS nella versione `5.x` e il backend remoto su S3, seguendo i requisiti di OpenTofu.

### `variables.tf`

```
variable "aws_region"    { default = "eu-south-1" }
variable "cluster_name"  { default = "shortener-cluster" }

variable "control_plane_instance_type" { default = "t3.small" }
variable "worker_instance_type"        { default = "t3.small" }
variable "worker_min_size"             { default = 2 }
variable "worker_max_size"             { default = 4 }

variable "ami_id" { default = "ami-09420cfad91ebef79" }
```

Le variabili costituiscono i parametri configurabili dell'infrastruttura. Il tipo di istanza `t3.small` è scelto per contenere i costi in ambiente di sviluppo. L'AMI corrisponde a Ubuntu 26.04 LTS in `eu-south-1`. Il cluster può scalare da 2 a 4 worker node. La `desired_capacity` è omessa dall'ASG, seguento le direttive della documentazione di OpenTofu.


### `vpc.tf`

Questo file definisce l'intera topologia di rete del cluster, realizzata mediante una VPC multi-AZ.

#### VPC e Internet Gateway

```
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
```

La VPC utilizza il CIDR `10.0.0.0/16`. `enable_dns_hostnames` è necessario affinché le istanze EC2 ricevano un hostname DNS risolvibile all'interno della VPC, requisito di Kubernetes per la comunicazione tra componenti. L'Internet Gateway è il punto di ingresso e uscita della VPC verso Internet.

#### Subnet pubbliche e private

```
resource "aws_subnet" "public" {
  count                   = 2
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  count             = 2
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
}
```

Vengono create quattro subnet distribuite su due Availability Zone, per garantire alta disponibilità a livello di rete:

- le subnet pubbliche (`10.0.0.0/24`, `10.0.1.0/24`) ospitano i nodi del NLB. `map_public_ip_on_launch` assegna automaticamente un IP pubblico a ogni risorsa creata in queste subnet.
- le subnet private (`10.0.10.0/24`, `10.0.11.0/24`) ospitano il control plane e i worker node. Non sono raggiungibili direttamente da Internet.

Il data source `aws_availability_zones` richiede ad AWS le AZ disponibili nella regione.

#### NAT Gateway ed Elastic IP

```
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]
}
```

Le istanze nelle subnet private non hanno IP pubblici e non sono direttamente raggiungibili da Internet, ma devono poter effettuare connessioni uscenti per scaricare pacchetti durante l'avvio e per il recupero delle immagini da ECR. Il NAT Gateway risolve questo problema, permettendo una comunicazione undiirezionale con Internet. Requisito del NAT Gateway è un Elastic IP. La direttiva `depends_on` evita problemi di dipendenze alla creazione.

#### Route table

```
resource "aws_route_table" "public" {
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}
```

Ogni subnet ha una route table associata che definisce come instradare il traffico:

- la route table pubblica dirige tutto il traffico non locale (`0.0.0.0/0`) verso l'Internet Gateway;
- la route table privata dirige il traffico uscente verso il NAT Gateway, permettendo alle istanze private di accedere a internet senza essere esposte.

### `sg.tf`

```
resource "aws_security_group" "k8s" {
  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Intra-cluster traffic ingress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

Viene utilizzato un unico security group condiviso da tutte le istanze del cluster. Le regole definite sono:

- porta `6443` per permettere l'accesso all'API server di Kubernetes tramite `kubectl`;
- porte `30000-32767` per i NodePort di Kubernetes, necessario affinché il NLB possa inoltrare il traffico applicativo ai worker;
- traffico intra-cluster** (`self = true`) per permettere tutto il traffico tra le istanze che condividono questo security group. È fondamentale per la comunicazione interna del cluster;
- egress libero, così che le istanze possono effettuare connessioni uscenti senza restrizioni.

### `iam.tf`

Le istanze EC2 necessitano di ruoli IAM per interagire con le API AWS senza la necessità di inserire credenziali per l'autenticazione con i servizi.

#### Control plane

```
resource "aws_iam_role" "control_plane" {
  name = "${var.cluster_name}-control-plane-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "control_plane_ssm" {
  name = "ssm-policy"
  role = aws_iam_role.control_plane.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/k8s/*"
    },
    {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }]
  })
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "${var.cluster_name}-control-plane-profile"
  role = aws_iam_role.control_plane.name
}
```

`aws_iam_role` definisce l'entità in grado di poter assumere il ruolo, ossia il servizio EC2. In particolare, il ruolo del control plane ha il permesso di scrivere e leggere parametri su SSM Parameter Store sotto il path `/k8s/*`. Questo è necessario per salvare il join command e il kubeconfig al termine del bootstrap, rendendoli disponibili rispettivamente ai worker e al workflow di GitHub Actions. I permessi KMS servono per cifrare e decifrare i parametri di tipo `SecureString`.

#### Worker node

```
resource "aws_iam_role" "workers" {
  name = "${var.cluster_name}-workers-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "workers_ssm_ecr" {
  name = "ssm-ecr-policy"
  role = aws_iam_role.workers.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/k8s/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "workers" {
  name = "${var.cluster_name}-workers-profile"
  role = aws_iam_role.workers.name
}
```

I worker hanno i seguenti permessi:

- `ssm:GetParameter` per leggere il join command durante la configurazione;
- `ecr:`, con i permessi per autenticarsi sul registry e scaricare le immagini Docker dei container applicativi;
- `kms:Decrypt` per decifrare il join command salvato come `SecureString`.

### `instances.tf` 

Il file definise le istanze di control plane e dei worker e il file di user data per la configurazione all'avvio.

#### Control plane

```
resource "aws_instance" "control_plane" {
  ami                    = var.ami_id
  instance_type          = var.control_plane_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.k8s.id]
  iam_instance_profile   = aws_iam_instance_profile.control_plane.name
  depends_on             = [aws_nat_gateway.main]

  user_data = base64encode(templatefile("${path.module}/control-plane-userdata.tftpl", {
    aws_region = var.aws_region
    nlb_dns    = aws_lb.main.dns_name
    pod_cidr   = "10.244.0.0/16"
  }))
}

resource "aws_lb_target_group_attachment" "control_plane_api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.control_plane.id
  port             = 6443
}
```

Il control plane è una singola istanza EC2 nella prima subnet privata. La scelta di non usare un ASG evita situazioni in cui il numero di control plane è pari, causando la perdita del quorum. Il `depends_on` sul NAT Gateway è necessario, in quanto senza di esso l'istanza potrebbe avviarsi prima che il NAT sia operativo, causando il fallimento del download dei pacchetti durante il bootstrap.

Il `templatefile` inietta nel cloudinit script il DNS del NLB (necessario per configurare l'endpoint del cluster), il CIDR della rete pod di Flannel e la regione AWS.

Il control plane viene anche registrato come target del target group API del NLB tramite `aws_lb_target_group_attachment`.

#### Worker node — Launch Template e ASG

```
resource "aws_launch_template" "workers" {
  image_id      = var.ami_id
  instance_type = var.worker_instance_type

  iam_instance_profile { name = aws_iam_instance_profile.workers.name }
  vpc_security_group_ids = [aws_security_group.k8s.id]

  user_data = base64encode(templatefile("${path.module}/worker-userdata.tftpl", {
    aws_region = var.aws_region
  }))
}

resource "aws_autoscaling_group" "workers" {
  min_size            = var.worker_min_size
  max_size            = var.worker_max_size
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.http.arn]

  depends_on = [aws_nat_gateway.main]

  launch_template {
    id      = aws_launch_template.workers.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences { min_healthy_percentage = 50 }
  }
}
```

I worker node usano un Launch Template per l'ASG. L'ASG gestisce automaticamente il numero di istanze all'interno del range `[min_size, max_size]` e le distribuisce tra le subnet private, garantendo la distribuzione su più AZ. `target_group_arns` collega l'ASG al target group HTTP del NLB: ogni nuova istanza viene automaticamente registrata come target e inizia a ricevere traffico. Infine, `instance_refresh` con strategia `Rolling` garantisce che gli aggiornamenti alla Launch Template vengano applicati sostituendo i nodi uno alla volta, mantenendo almeno il 50% delle istanze operative durante il processo.

#### Policy di autoscaling

```
resource "aws_autoscaling_policy" "scale_up" {
  adjustment_type    = "ChangeInCapacity"
  scaling_adjustment = 1
  cooldown           = 120
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  metric_name         = "CPUUtilization"
  threshold           = 70
  evaluation_periods  = 2
  period              = 120
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_autoscaling_policy" "scale_down" {
  adjustment_type    = "ChangeInCapacity"
  scaling_adjustment = -1
  cooldown           = 120
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  metric_name         = "CPUUtilization"
  threshold           = 30
  evaluation_periods  = 2
  period              = 120
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
}
```

Lo scaling automatico è gestito tramite allarmi CloudWatch collegati a policy di tipo `ChangeInCapacity`:

- se l'uso medio della CPU supera il 70%, viene aggiunto un nodo.
- se l'uso medio della CPU scende sotto il 30%, viene rimosso un nodo.

Il cooldown di 120 secondi impedisce scaling eccessivamente frequenti, dando tempo al cluster di stabilizzarsi dopo ogni modifica. `evaluation_periods = 2` riduce i falsi positivi causati da picchi temporanei, richiedendo la valutazione in periodi di due minuti.

### `nlb.tf`

```
resource "aws_lb" "main" {
  name               = "${var.cluster_name}-nlb"
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id
  internal           = false
  tags               = { Name = "${var.cluster_name}-nlb" }
}

resource "aws_lb_target_group" "http" {
  name     = "${var.cluster_name}-http"
  port     = 30080
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id

  health_check {
    protocol = "TCP"
    port     = 30080
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_target_group" "api" {
  name     = "${var.cluster_name}-api"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id

  health_check {
    protocol = "TCP"
    port     = 6443
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.main.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
```

Il NLB è il punto di ingresso pubblico del cluster. Viene posizionato nelle subnet pubbliche, dove crea un nodo (NLB node) con la propria interfaccia di rete in ciascuna AZ. Questo garantisce alta disponibilità, facendo sì che il traffico venga automaticamente instradato al nodo nell'altra AZ se una AZ non è disponibile.

Sono configurati due listener e relativi target group:

- porta 80 verso porta 30080, per instradare il traffico HTTP verso i worker node nella porta esposta dall'Ingress Controller;
- porta 6443 verso porta 6443 per il traffico verso l'API server di Kubernetes sul control plane. Questo permette l'uso di `kubectl` dall'esterno e dal workflow di GitHub Actions.

I health check TCP verificano che le porte di destinazione siano raggiungibili prima di instradare il traffico.

### `ecr.tf`

```
resource "aws_ecr_repository" "frontend" {
  name                 = "shortener-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "backend" {
  name                 = "shortener-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "${var.cluster_name}-backend" }
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantieni solo 10 immagini"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantieni solo 10 immagini"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

Vengono creati due repository ECR privati — uno per il frontend e uno per il backend. `image_tag_mutability = "MUTABLE"` permette di sovrascrivere tag esistenti, mentre `scan_on_push = true` attiva la scansione automatica delle immagini per vulnerabilità note ad ogni push.

`force_delete = true` permette a OpenTofu di eliminare i repository anche se contengono immagini durante un `tofu destroy`, semplificando il teardown dell'infrastruttura.

La lifecycle policy mantiene al massimo 10 immagini per repository, eliminando automaticamente le più vecchie per contenere i costi di storage.

### `control-plane-userdata.tftpl`

Lo script di bootstrap è eseguito automaticamente al primo avvio dell'istanza tramite cloud-init. Svolge le seguenti operazioni in sequenza:

- installa i pacchetti necessari, disabilita lo swap (requisito obbligatorio di Kubernetes), e carica i moduli kernel `overlay` e `br_netfilter`. Configura i parametri sysctl per abilitare il forwarding IP e il filtraggio del traffico bridge per il networking dei pod;
- installa containerd dal repository Docker ufficiale. Genera la configurazione di default e abilita `SystemdCgroup = true`, necessario affinché containerd e Kubernetes usino lo stesso cgroup driver (systemd), evitando conflitti nella gestione delle risorse;
- installa `kubelet`, `kubeadm` e `kubectl` dalla versione 1.36 del repository ufficiale Kubernetes. `apt-mark hold` blocca gli aggiornamenti automatici di questi pacchetti;
- recupera l'IP privato tramite IMDSv2, usando il metadata service;
- inizializza il cluster, impostando come endpoint il DNS del NLB, aggiungendolo al certificato TLS dell'API server. Come CIDR del cluster viene specificato il CIDR per Flannel;
- installa Flannel, Nginx ingress e il metrics server;
- salva su SSM il comando per unirsi al cluster e il kubeconfig;

### `worker-userdata.tftpl`

Il bootstrap dei worker segue gli stessi passi iniziali del control plane per l'installazione di containerd e kubelet. Tuttavia:

- viene configurato l'ECR credential provider per kubelet, che permette di autenticarsi automaticamente su ECR usando il profilo IAM dell'istanza;
- viene prelevato il comando di unione al cluster per i worker.

## Analisi dei workflow

Sono presenti tre workflow nella repository Github:

- `infra.yaml` per il deployment e aggiornamento dell'infrastruttura;
- `app-cicd.yaml` per la gestione delle modifiche dell'applicazione;
- `destroy.yaml` per la distruzione dell'infrastruttura.

Il workflow `infra.yaml` e `destroy.yaml` vengono eseguiti nell'environment `production`, che richiede un'approvazione manuale. Per configurare l'ambiente, basta andare in `Settings > Environments > New Environment` e configurare l'ambiente in modo tale da accettare approvazioni di reviewer.

### `infra.yaml`

Il workflow prevede due job: `plan` e `apply`. 

`plan` viene eseguito solamente quando si effettua un Pull Request sul branch `main` alla cartella che contiene i file dell'infrastruttura. Il workflow esegue il comando `tofu plan` e inserisce il risultato come commento della Pull Request. L'obiettivo del job è quello di fornire un'idea ai reviewer delle modifiche sull'infrastruttura.

`apply` applica le modifiche all'infrastruttura con OpenTofu e prevela il file `kubeconfig` per applicare il segreto `POSTGRE_SECRET` per il setup del database. L'applicazione del segreto è idempotente mediante l'utilizzo di un manifest creato *on-the-fly*.

### `app-cicd.yaml`

La repository contiene anche i file applicativi nella cartella `application`. Il workflow `app-cicd.yaml` permette un deployment continuo delle modifiche, costruendo le immagini del front-end e del back-end se vengono rilevate delle modifiche, e applicando i manifest presenti nella cartella `application/k8s`. I manifest sono stati inclusi nel folder dell'applicazione, in quanto i cambiamenti delle applicazioni potrebbero richiedere potenzialmente anche cambiamenti nella gestione delle repliche o delle politiche di scaling dell'applicazione ove necessario.

### `destroy.yaml`

Alla fine della costruzione dell'infrastruttura, è possibile distruggere il progetto dimostrativo eseguendo `destroy.yaml`.
