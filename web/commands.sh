
aws s3 cp web/ops_dark.html s3://training.yikyakyuk.com/ops/index.html
aws s3 cp web/instances.json s3://training.yikyakyuk.com/ops/instances.json

aws s3 sync diagrams/ s3://training.yikyakyuk.com/ops/img/ --exclude "*" --include "*.png"
