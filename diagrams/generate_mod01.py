"""
Generate architecture diagram for Module 01: Well-Architected Framework Review
"""
import os

os.environ["PATH"] = (
    r"D:\Users\erictole\OneDrive - amazon.com\demo\cloud-operations-on-aws"
    r"\graphviz\Graphviz-12.2.1-win64\bin;" + os.environ.get("PATH", "")
)

from diagrams import Diagram, Cluster, Edge
from diagrams.custom import Custom

BASE_DIR = r"D:\Users\erictole\OneDrive - amazon.com\demo\cloud-operations-on-aws"
ICONS_DIR = os.path.join(BASE_DIR, "aws-icons", "Architecture-Service-Icons_04302026")
OUTPUT_DIR = os.path.join(BASE_DIR, "diagrams")

def icon(category, filename):
    return os.path.join(ICONS_DIR, category, "48", filename)

# Icons
WELL_ARCH = icon("Arch_Management-Tools", "Arch_AWS-Well-Architected-Tool_48.png")
CLOUDFORMATION = icon("Arch_Management-Tools", "Arch_AWS-CloudFormation_48.png")

GRAPH_ATTR = {
    "fontsize": "14",
    "fontname": "Helvetica",
    "bgcolor": "#FFFFFF",
    "pad": "0.5",
    "nodesep": "0.8",
    "ranksep": "1.0",
    "splines": "curved",
}
EDGE_ATTR = {"color": "#555555", "penwidth": "1.5"}
NODE_ATTR = {"fontsize": "11", "fontname": "Helvetica"}


with Diagram(
    "Module 01: Well-Architected Framework Review",
    filename=os.path.join(OUTPUT_DIR, "mod01-well-architected"),
    show=False,
    direction="TB",
    graph_attr=GRAPH_ATTR,
    edge_attr=EDGE_ATTR,
    node_attr=NODE_ATTR,
):
    cfn = Custom("CloudFormation\n(deploy workload)", CLOUDFORMATION)
    workload = Custom("Well-Architected\nWorkload\n(CustomerPortal)", WELL_ARCH)

    with Cluster("Six Pillars Review", graph_attr={
        "style": "rounded", "color": "#FF9900", "fontcolor": "#FF9900"
    }):
        ops = Custom("Operational\nExcellence", WELL_ARCH)
        sec = Custom("Security", WELL_ARCH)
        rel = Custom("Reliability", WELL_ARCH)
        perf = Custom("Performance\nEfficiency", WELL_ARCH)
        cost = Custom("Cost\nOptimization", WELL_ARCH)
        sus = Custom("Sustainability", WELL_ARCH)

    with Cluster("Outputs", graph_attr={
        "style": "dashed", "color": "#3F8624", "fontcolor": "#3F8624"
    }):
        risk = Custom("Risk Report\n(HIGH / MEDIUM)", WELL_ARCH)
        milestone = Custom("Milestone\n(snapshot)", WELL_ARCH)

    cfn >> Edge(label="creates", color="#8C4FFF", style="bold") >> workload
    workload >> Edge(label="reviews", color="#FF9900") >> ops
    workload >> Edge(label="reviews", color="#FF9900") >> sec
    workload >> Edge(label="reviews", color="#FF9900") >> rel
    workload >> Edge(label="reviews", color="#FF9900") >> perf
    workload >> Edge(label="reviews", color="#FF9900") >> cost
    workload >> Edge(label="reviews", color="#FF9900") >> sus
    ops >> Edge(label="generates", color="#3F8624", style="dashed") >> risk
    risk >> Edge(label="tracks", color="#3F8624", style="dashed") >> milestone

print("  ✓ mod01-well-architected.png")
