"""
Generate architecture diagrams for all Cloud Operations on AWS modules.
Uses the diagrams library with custom AWS icons from the aws-icons folder.
"""
import os
import sys

# Base paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PARENT_DIR = os.path.dirname(BASE_DIR)
ICONS_DIR = os.path.join(PARENT_DIR, "aws-icons", "Architecture-Service-Icons_04302026")
GROUP_ICONS_DIR = os.path.join(PARENT_DIR, "aws-icons", "Architecture-Group-Icons_04302026")
OUTPUT_DIR = BASE_DIR

from diagrams import Diagram, Cluster, Edge
from diagrams.custom import Custom

# Icon paths helper
def icon(category, filename):
    return os.path.join(ICONS_DIR, category, "48", filename)

def group_icon(filename):
    return os.path.join(GROUP_ICONS_DIR, filename)

# Common icon paths
IAM = icon("Arch_Security-Identity", "Arch_AWS-Identity-and-Access-Management_48.png")
S3 = icon("Arch_Storage", "Arch_Amazon-Simple-Storage-Service_48.png")
EC2 = icon("Arch_Compute", "Arch_Amazon-EC2_48.png")
SSM = icon("Arch_Management-Tools", "Arch_AWS-Systems-Manager_48.png")
CONFIG = icon("Arch_Management-Tools", "Arch_AWS-Config_48.png")
CLOUDFORMATION = icon("Arch_Management-Tools", "Arch_AWS-CloudFormation_48.png")
CLOUDWATCH = icon("Arch_Management-Tools", "Arch_Amazon-CloudWatch_48.png")
CLOUDTRAIL = icon("Arch_Management-Tools", "Arch_AWS-CloudTrail_48.png")
AUTOSCALING = icon("Arch_Compute", "Arch_Amazon-EC2-Auto-Scaling_48.png")
ELB = icon("Arch_Networking-Content-Delivery", "Arch_Elastic-Load-Balancing_48.png")
VPC = icon("Arch_Networking-Content-Delivery", "Arch_Amazon-Virtual-Private-Cloud_48.png")
SNS = icon("Arch_Application-Integration", "Arch_Amazon-Simple-Notification-Service_48.png")
EVENTBRIDGE = icon("Arch_Application-Integration", "Arch_Amazon-EventBridge_48.png")
EBS = icon("Arch_Storage", "Arch_Amazon-Elastic-Block-Store_48.png")
EFS = icon("Arch_Storage", "Arch_Amazon-EFS_48.png")
FSX = icon("Arch_Storage", "Arch_Amazon-FSx_48.png")
BACKUP = icon("Arch_Storage", "Arch_AWS-Backup_48.png")
GLACIER = icon("Arch_Storage", "Arch_Amazon-Simple-Storage-Service-Glacier_48.png")
BUDGETS = icon("Arch_Cloud-Financial-Management", "Arch_AWS-Budgets_48.png")
COST_EXPLORER = icon("Arch_Cloud-Financial-Management", "Arch_AWS-Cost-Explorer_48.png")
TRUSTED_ADVISOR = icon("Arch_Management-Tools", "Arch_AWS-Trusted-Advisor_48.png")
COMPUTE_OPTIMIZER = icon("Arch_Management-Tools", "Arch_AWS-Compute-Optimizer_48.png")
KMS = icon("Arch_Security-Identity", "Arch_AWS-Key-Management-Service_48.png")
LAMBDA = icon("Arch_Compute", "Arch_AWS-Lambda_48.png")

# Diagram styling
GRAPH_ATTR = {
    "fontsize": "14",
    "fontname": "Helvetica",
    "bgcolor": "#FFFFFF",
    "pad": "0.5",
    "nodesep": "0.8",
    "ranksep": "1.2",
    "splines": "curved",
    "rankdir": "LR",
}
EDGE_ATTR = {
    "color": "#555555",
    "penwidth": "1.5",
}
NODE_ATTR = {
    "fontsize": "11",
    "fontname": "Helvetica",
}

# ============================================================
# Module 02: Access Management - IAM Policy Evaluation
# ============================================================
def mod02_access_management():
    with Diagram(
        "Module 02: IAM Policy Evaluation",
        filename=os.path.join(OUTPUT_DIR, "mod02-access-management"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        user = Custom("IAM User\n(demo-user)", IAM)

        allow = Custom("Allow S3 Read\n(Explicit Allow)", IAM)
        deny = Custom("Deny Confidential\n(Explicit Deny)", IAM)

        general = Custom("general-bucket\n✅ Allowed", S3)
        confidential = Custom("confidential-bucket\n❌ Denied", S3)

        role = Custom("EmergencyAdmin\nRole (STS)", IAM)

        user >> Edge(label="attached", color="#FF9900", style="bold") >> allow
        user >> Edge(label="attached", color="#DD3522", style="bold") >> deny
        allow >> Edge(label="allows all S3", color="#3F8624") >> general
        deny >> Edge(label="DENY wins", color="#DD3522", style="bold") >> confidential
        user >> Edge(label="sts:AssumeRole", color="#8C4FFF", style="dashed") >> role

    print("  ✓ mod02-access-management.png")

# ============================================================
# Module 03: System Discovery
# ============================================================
def mod03_system_discovery():
    with Diagram(
        "Module 03: System Discovery",
        filename=os.path.join(OUTPUT_DIR, "mod03-system-discovery"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        ssm = Custom("Session Manager\n(secure shell)", SSM)
        instance = Custom("EC2 Instance\n(SSM Agent)", EC2)
        inventory = Custom("SSM Inventory\n(Software, OS)", SSM)
        config = Custom("AWS Config\n(Compliance)", CONFIG)

        ssm >> Edge(label="no SSH needed", color="#ED7100") >> instance >> Edge(label="collects", color="#3F8624") >> inventory
        instance >> Edge(label="evaluates rules", color="#8C4FFF") >> config

    print("  ✓ mod03-system-discovery.png")

# ============================================================
# Module 04: Deploy and Update Resources
# ============================================================
def mod04_deploy_update():
    with Diagram(
        "Module 04: Tag, Image, Deploy",
        filename=os.path.join(OUTPUT_DIR, "mod04-deploy-update"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        with Cluster("1. Base Instance", graph_attr={"style": "rounded", "color": "#ED7100", "fontcolor": "#ED7100"}):
            base = Custom("WebServer-Base\n(httpd installed)", EC2)

        with Cluster("2. Golden AMI", graph_attr={"style": "rounded", "color": "#8C4FFF", "fontcolor": "#8C4FFF"}):
            ami = Custom("GoldenAMI\n-WebServer v1.0", EC2)

        with Cluster("3. Production Fleet", graph_attr={"style": "rounded", "color": "#3F8624", "fontcolor": "#3F8624"}):
            prod1 = Custom("WebServer-1\n(from AMI)", EC2)
            prod2 = Custom("WebServer-2\n(from AMI)", EC2)

        tags = Custom("Resource Tags\n& Groups", SSM)

        base >> Edge(label="create-image", color="#8C4FFF", style="bold") >> ami
        ami >> Edge(label="launch", color="#3F8624") >> prod1
        ami >> Edge(label="launch", color="#3F8624") >> prod2
        tags >> Edge(label="organize", color="#FF9900", style="dashed") >> base
        tags >> Edge(label="organize", color="#FF9900", style="dashed") >> prod1

    print("  ✓ mod04-deploy-update.png")

# ============================================================
# Module 05: Automate Resource Deployment (CloudFormation)
# ============================================================
def mod05_automate_deployment():
    with Diagram(
        "Module 05: Infrastructure as Code with CloudFormation",
        filename=os.path.join(OUTPUT_DIR, "mod05-automate-deployment"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        cfn = Custom("CloudFormation\nStack", CLOUDFORMATION)
        vpc = Custom("VPC + Subnet\n+ Security Group", VPC)
        instance = Custom("EC2 Instance\n(WebServer)", EC2)
        drift = Custom("Drift Detection\n& Change Sets", CLOUDFORMATION)

        cfn >> Edge(label="creates", color="#3F8624", style="bold") >> vpc
        vpc >> Edge(label="hosts", color="#3F8624") >> instance
        cfn >> Edge(label="monitors drift", color="#FF9900", style="dashed") >> drift

    print("  ✓ mod05-automate-deployment.png")

# ============================================================
# Module 06: Manage Resources (Systems Manager)
# ============================================================
def mod06_manage_resources():
    with Diagram(
        "Module 06: Operations as Code with Systems Manager",
        filename=os.path.join(OUTPUT_DIR, "mod06-manage-resources"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        run_cmd = Custom("Run Command", SSM)
        ec2_fleet = Custom("EC2 Fleet\n(by tag)", EC2)
        param_store = Custom("Parameter Store\n(configs & secrets)", SSM)
        kms = Custom("KMS\n(encryption)", KMS)
        maint_win = Custom("Maintenance\nWindows", SSM)

        run_cmd >> Edge(label="remote exec at scale", color="#ED7100") >> ec2_fleet
        ec2_fleet >> Edge(label="scheduled patching", color="#8C4FFF", style="dashed") >> maint_win
        param_store >> Edge(label="encrypted values", color="#DD3522", style="dashed") >> kms

    print("  ✓ mod06-manage-resources.png")

# ============================================================
# Module 07: Configure Highly Available Systems
# ============================================================
def mod07_high_availability():
    with Diagram(
        "Module 07: Load Balancing & High Availability",
        filename=os.path.join(OUTPUT_DIR, "mod07-high-availability"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        users = Custom("Users", IAM)
        alb = Custom("Application\nLoad Balancer", ELB)
        web1 = Custom("Web-AZ1\n(httpd)", EC2)
        web2 = Custom("Web-AZ2\n(httpd)", EC2)

        users >> Edge(label="HTTP", color="#555555", style="bold") >> alb
        alb >> Edge(label="health check + forward", color="#ED7100") >> web1
        alb >> Edge(label="health check + forward", color="#3F8624") >> web2

    print("  ✓ mod07-high-availability.png")

# ============================================================
# Module 08: Automate Scaling
# ============================================================
def mod08_automate_scaling():
    with Diagram(
        "Module 08: Auto Scaling with Target Tracking",
        filename=os.path.join(OUTPUT_DIR, "mod08-automate-scaling"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        cw = Custom("CloudWatch\n(CPU > 50%)", CLOUDWATCH)
        asg = Custom("Auto Scaling Group\nMin=1, Max=4", AUTOSCALING)
        template = Custom("Launch Template\nt3.micro + httpd", EC2)
        fleet = Custom("Scaled Fleet\n(Multi-AZ)", EC2)

        cw >> Edge(label="triggers", color="#DD3522", style="bold") >> asg
        asg >> Edge(label="uses", color="#8C4FFF") >> template
        template >> Edge(label="launches", color="#3F8624") >> fleet

    print("  ✓ mod08-automate-scaling.png")

# ============================================================
# Module 09: Monitor and Maintain System Health
# ============================================================
def mod09_monitoring():
    with Diagram(
        "Module 09: CloudWatch Monitoring Pipeline",
        filename=os.path.join(OUTPUT_DIR, "mod09-monitoring"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        instance = Custom("EC2 Instance\n(application)", EC2)

        with Cluster("CloudWatch", graph_attr={"style": "rounded", "color": "#ED7100", "fontcolor": "#ED7100"}):
            metrics = Custom("Metrics\n(CPU, Custom)", CLOUDWATCH)
            alarms = Custom("Alarms\n(threshold)", CLOUDWATCH)
            logs = Custom("Logs\n(centralized)", CLOUDWATCH)

        sns = Custom("SNS\n(notifications)", SNS)
        metric_filter = Custom("Metric Filter\n(ERROR count)", CLOUDWATCH)

        instance >> Edge(label="sends metrics", color="#3F8624") >> metrics
        instance >> Edge(label="streams logs", color="#8C4FFF") >> logs
        metrics >> Edge(label="triggers", color="#DD3522", style="bold") >> alarms
        alarms >> Edge(label="notifies", color="#FF9900") >> sns
        logs >> Edge(label="pattern match", color="#8C4FFF", style="dashed") >> metric_filter
        metric_filter >> Edge(label="creates metric", color="#ED7100", style="dashed") >> metrics

    print("  ✓ mod09-monitoring.png")

# ============================================================
# Module 10: Data Security and System Auditing
# ============================================================
def mod10_security_auditing():
    with Diagram(
        "Module 10: Detect, Alert, Remediate",
        filename=os.path.join(OUTPUT_DIR, "mod10-security-auditing"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        with Cluster("AWS API Activity", graph_attr={"style": "dashed", "color": "#555555", "fontcolor": "#555555"}):
            api_call = Custom("API Calls\n(all actions)", IAM)

        cloudtrail = Custom("CloudTrail\n(audit log)", CLOUDTRAIL)
        eventbridge = Custom("EventBridge\n(real-time rules)", EVENTBRIDGE)
        config = Custom("AWS Config\n(compliance)", CONFIG)
        sns = Custom("SNS\n(alert)", SNS)

        with Cluster("Auto-Remediation", graph_attr={"style": "rounded", "color": "#DD3522", "fontcolor": "#DD3522"}):
            remediate = Custom("SSM Automation\n(revoke SG rule)", SSM)

        api_call >> Edge(label="records", color="#8C4FFF") >> cloudtrail
        cloudtrail >> Edge(label="triggers", color="#ED7100", style="bold") >> eventbridge
        eventbridge >> Edge(label="alerts", color="#FF9900") >> sns
        config >> Edge(label="evaluates", color="#DD3522") >> api_call
        config >> Edge(label="auto-fix", color="#DD3522", style="bold") >> remediate

    print("  ✓ mod10-security-auditing.png")

# ============================================================
# Module 11: Operating Secure Resilient Networks
# ============================================================
def mod11_secure_networks():
    with Diagram(
        "Module 11: VPC Security Layers",
        filename=os.path.join(OUTPUT_DIR, "mod11-secure-networks"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        internet = Custom("Internet", VPC)
        igw = Custom("Internet\nGateway", VPC)
        nacl_pub = Custom("NACL\n(stateless)", VPC)
        sg_pub = Custom("Security Group\n(stateful)", VPC)
        pub_instance = Custom("Web Server\n(public)", EC2)
        priv_instance = Custom("Backend\n(private)", EC2)
        flow_logs = Custom("VPC Flow Logs", CLOUDWATCH)

        internet >> Edge(color="#555555", style="bold") >> igw
        igw >> Edge(label="route", color="#3F8624") >> nacl_pub
        nacl_pub >> Edge(label="subnet filter", color="#8C4FFF") >> sg_pub
        sg_pub >> Edge(label="instance filter", color="#ED7100") >> pub_instance
        pub_instance >> Edge(label="private only", color="#DD3522", style="dashed") >> priv_instance
        igw >> Edge(label="logs traffic", color="#FF9900", style="dashed") >> flow_logs

    print("  ✓ mod11-secure-networks.png")

# ============================================================
# Module 12: Mountable Storage
# ============================================================
def mod12_mountable_storage():
    with Diagram(
        "Module 12: EBS, Snapshots & Shared Storage",
        filename=os.path.join(OUTPUT_DIR, "mod12-mountable-storage"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        instance = Custom("EC2 Instance", EC2)
        ebs = Custom("EBS Volumes\n(gp3, io2)", EBS)
        snapshot = Custom("EBS Snapshots\n(incremental)", EBS)
        efs = Custom("Amazon EFS\n(shared NFS)", EFS)

        instance >> Edge(label="attach", color="#3F8624", style="bold") >> ebs
        ebs >> Edge(label="snapshot", color="#8C4FFF") >> snapshot
        instance >> Edge(label="mount", color="#ED7100", style="dashed") >> efs

    print("  ✓ mod12-mountable-storage.png")

# ============================================================
# Module 13: Object Storage - S3 Lifecycle
# ============================================================
def mod13_object_storage():
    with Diagram(
        "Module 13: S3 Lifecycle & Data Protection",
        filename=os.path.join(OUTPUT_DIR, "mod13-object-storage"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        with Cluster("S3 Storage Classes", graph_attr={"style": "rounded", "color": "#3F8624", "fontcolor": "#3F8624"}):
            standard = Custom("S3 Standard\n(hot data)", S3)
            ia = Custom("S3 Standard-IA\n(30+ days)", S3)
            glacier = Custom("S3 Glacier\n(90+ days)", GLACIER)

        with Cluster("Data Protection", graph_attr={"style": "rounded", "color": "#8C4FFF", "fontcolor": "#8C4FFF"}):
            versioning = Custom("Versioning\n(all versions kept)", S3)
            lifecycle = Custom("Lifecycle Policy\n(auto-transition)", S3)

        standard >> Edge(label="30 days", color="#FF9900", style="bold") >> ia
        ia >> Edge(label="90 days", color="#ED7100", style="bold") >> glacier
        lifecycle >> Edge(label="automates\ntransitions", color="#8C4FFF", style="dashed") >> standard
        versioning >> Edge(label="protects\nfrom deletion", color="#DD3522", style="dashed") >> standard

    print("  ✓ mod13-object-storage.png")

# ============================================================
# Module 14: Cost Reporting, Alerts, Optimization
# ============================================================
def mod14_cost_optimization():
    with Diagram(
        "Module 14: Cost Awareness, Control & Optimization",
        filename=os.path.join(OUTPUT_DIR, "mod14-cost-optimization"),
        show=False,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        edge_attr=EDGE_ATTR,
        node_attr=NODE_ATTR,
    ):
        cost_explorer = Custom("Cost Explorer\n(trends & forecast)", COST_EXPLORER)
        budgets = Custom("AWS Budgets\n($100/month)", BUDGETS)
        sns = Custom("SNS\n(email alerts)", SNS)
        trusted_adv = Custom("Trusted Advisor\n& Compute Optimizer", TRUSTED_ADVISOR)

        cost_explorer >> Edge(label="informs", color="#3F8624", style="dashed") >> budgets
        budgets >> Edge(label="80% threshold", color="#FF9900", style="bold") >> sns
        trusted_adv >> Edge(label="recommends rightsizing", color="#8C4FFF", style="dashed") >> sns

    print("  ✓ mod14-cost-optimization.png")

# ============================================================
# Main execution
# ============================================================
if __name__ == "__main__":
    print("Generating architecture diagrams...")
    print("=" * 50)
    
    mod02_access_management()
    mod03_system_discovery()
    mod04_deploy_update()
    mod05_automate_deployment()
    mod06_manage_resources()
    mod07_high_availability()
    mod08_automate_scaling()
    mod09_monitoring()
    mod10_security_auditing()
    mod11_secure_networks()
    mod12_mountable_storage()
    mod13_object_storage()
    mod14_cost_optimization()
    
    print("=" * 50)
    print(f"All diagrams generated in: {OUTPUT_DIR}")
    print("Done!")
