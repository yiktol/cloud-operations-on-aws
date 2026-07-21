"""
Generate architecture diagram for Module 01: Well-Architected Framework Review
"""
import os

from diagrams import Diagram, Cluster, Edge
from diagrams.custom import Custom

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PARENT_DIR = os.path.dirname(BASE_DIR)
ICONS_DIR = os.path.join(PARENT_DIR, "aws-icons", "Architecture-Service-Icons_04302026")
OUTPUT_DIR = BASE_DIR

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
    "ranksep": "1.2",
    "splines": "curved",
    "rankdir": "LR",
}
EDGE_ATTR = {"color": "#555555", "penwidth": "1.5"}
NODE_ATTR = {"fontsize": "11", "fontname": "Helvetica"}


with Diagram(
    "Module 01: Well-Architected Framework Review",
    filename=os.path.join(OUTPUT_DIR, "mod01-well-architected"),
    show=False,
    direction="LR",
    graph_attr=GRAPH_ATTR,
    edge_attr=EDGE_ATTR,
    node_attr=NODE_ATTR,
):
    cfn = Custom("CloudFormation\n(deploy workload)", CLOUDFORMATION)
    workload = Custom("Well-Architected\nWorkload", WELL_ARCH)
    pillars = Custom("Six Pillars Review\n(Ops, Sec, Rel, Perf, Cost, Sus)", WELL_ARCH)
    risk = Custom("Risk Report\n& Milestone", WELL_ARCH)

    cfn >> Edge(label="creates", color="#8C4FFF", style="bold") >> workload
    workload >> Edge(label="reviews pillars", color="#FF9900") >> pillars
    pillars >> Edge(label="generates", color="#3F8624", style="dashed") >> risk

print("  ✓ mod01-well-architected.png")
