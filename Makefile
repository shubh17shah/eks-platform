# =============================================================================
# eks-platform — operational Makefile
#
# Wraps the two Terraform roots (bootstrap/ and terraform/) plus the AWS CLI /
# kubectl commands needed to stand the cluster up, inspect it, and tear it
# back down. Run `make` or `make help` for the full target list.
#
#   COST: the EKS control plane bills $0.10/hour from the moment `make up`
#   finishes until `make down` completes — there is no free tier, and it
#   bills whether or not anything is running on the cluster. See
#   docs/COST.md before you walk away from a running cluster.
# =============================================================================

SHELL         := /bin/bash
.DEFAULT_GOAL := help

TF_DIR        := terraform
BOOTSTRAP_DIR := bootstrap
REGION        := ap-south-1
CLUSTER_NAME  := eks-platform

.PHONY: help bootstrap init fmt validate lint plan up kubeconfig status down destroy-check cost

help: ## Show this help
	@echo "eks-platform — Makefile targets"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Typical flow:"
	@echo "  bootstrap -> (paste backend_config into terraform/backend.tf) -> init -> plan -> up -> kubeconfig -> ... -> down -> destroy-check"
	@echo ""
	@echo "Offline sanity check (no AWS credentials needed): make validate"

bootstrap: ## One-time: create the S3 state bucket + DynamoDB lock table (local state)
	cd $(BOOTSTRAP_DIR) && terraform init && terraform apply
	@echo ""
	@echo "-----------------------------------------------------------------"
	@echo " Copy the 'backend_config' output above into terraform/backend.tf"
	@echo " (that file does not exist yet — this is a manual, one-time step,"
	@echo " a chicken-and-egg fix: the backend can't store its own state)."
	@echo " Then run: make init"
	@echo "-----------------------------------------------------------------"

init: ## Initialize the main stack (needs terraform/backend.tf from the bootstrap output)
	cd $(TF_DIR) && terraform init

fmt: ## Format all Terraform files in place
	cd $(TF_DIR) && terraform fmt -recursive
	cd $(BOOTSTRAP_DIR) && terraform fmt -recursive

validate: ## Validate Terraform syntax/config — works WITHOUT AWS credentials
	cd $(TF_DIR) && terraform init -backend=false -input=false && terraform validate

lint: ## Run tflint if installed (best-effort static analysis, non-fatal if missing)
	@if command -v tflint >/dev/null 2>&1; then \
		cd $(TF_DIR) && tflint --init >/dev/null 2>&1; \
		cd $(TF_DIR) && tflint; \
	else \
		echo "tflint not found on PATH — skipping."; \
		echo "Install it from https://github.com/terraform-linters/tflint if you want this target to do something."; \
	fi

plan: ## Show the Terraform execution plan (requires AWS credentials + terraform/backend.tf)
	cd $(TF_DIR) && terraform plan

up: ## terraform apply — THIS STARTS THE $0.10/hr EKS BILLING CLOCK
	@echo "=============================================================="
	@echo "  WARNING: applying now starts the EKS control-plane billing"
	@echo "  clock — \$$0.10/hour, NO free tier, billed until 'make down'"
	@echo "  finishes. SPOT nodes, EBS volumes, and public IPs add more"
	@echo "  on top (~\$$0.13/hr all-in for this config)."
	@echo ""
	@echo "  Run 'make cost' for the full breakdown before continuing."
	@echo "=============================================================="
	cd $(TF_DIR) && terraform apply
	@echo ""
	@echo "Cluster applied. Point kubectl at it with:"
	@echo "  make kubeconfig"
	@echo "Remember: run 'make down' when you're done — this does not stop on its own."

kubeconfig: ## Point kubectl at the cluster (uses the terraform output, not a hardcoded name)
	cd $(TF_DIR) && eval "$$(terraform output -raw configure_kubectl)"

status: ## Show Terraform outputs + live cluster/node status
	@echo "--- Terraform outputs ($(TF_DIR)) ---"
	@cd $(TF_DIR) && terraform output 2>/dev/null || echo "(no state yet — run 'make up')"
	@echo ""
	@echo "--- kubectl ---"
	@kubectl get nodes -o wide 2>/dev/null || echo "(kubectl not configured against this cluster — run 'make kubeconfig')"

down: ## terraform destroy -auto-approve — stops the billing clock
	@echo "=============================================================="
	@echo "  Destroying all Terraform-managed resources in $(TF_DIR)/"
	@echo "  (auto-approved, no confirmation prompt)."
	@echo "=============================================================="
	cd $(TF_DIR) && terraform destroy -auto-approve
	@echo ""
	@echo "Destroy finished. Run 'make destroy-check' to confirm nothing billable is left."
	@echo "Note: if anything was installed with kubectl/helm outside Terraform (an"
	@echo "Ingress/LoadBalancer Service, for example), it will NOT be cleaned up here"
	@echo "and can keep an ALB and its ENIs alive indefinitely — delete those first next time."

destroy-check: ## Verify no EKS/EC2/ELB/NAT resources are left running in $(REGION)
	@command -v aws >/dev/null 2>&1 || { echo "FAIL: aws CLI not found — cannot verify anything"; exit 1; }
	@aws sts get-caller-identity >/dev/null 2>&1 || { echo "FAIL: no valid AWS credentials — cannot verify anything"; exit 1; }
	@echo "Checking $(REGION) for leftover billable resources..."
	@echo ""
	@echo "-- EKS cluster '$(CLUSTER_NAME)' --"
	@if aws eks list-clusters --region $(REGION) --query 'clusters' --output text 2>/dev/null \
		| tr '\t' '\n' | grep -qx "$(CLUSTER_NAME)"; then \
		echo "FAIL: cluster '$(CLUSTER_NAME)' still exists"; \
	else \
		echo "PASS: no cluster named '$(CLUSTER_NAME)'"; \
	fi
	@echo ""
	@echo "-- EC2 instances tagged Project=$(CLUSTER_NAME) --"
	@instances=$$(aws ec2 describe-instances --region $(REGION) \
		--filters "Name=tag:Project,Values=$(CLUSTER_NAME)" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
		--query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null); \
	if [ -z "$$instances" ]; then echo "PASS: no EC2 instances tagged Project=$(CLUSTER_NAME)"; \
	else echo "FAIL: instances present -> $$instances"; fi
	@echo ""
	@echo "-- Load balancers (region-wide check: $(REGION)) --"
	@albs=$$(aws elbv2 describe-load-balancers --region $(REGION) --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null); \
	clbs=$$(aws elb describe-load-balancers --region $(REGION) --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text 2>/dev/null); \
	if [ -z "$$albs" ] && [ -z "$$clbs" ]; then echo "PASS: no ALB/NLB/classic load balancers in $(REGION)"; \
	else echo "FAIL: load balancers present -> ALB/NLB: $$albs | classic: $$clbs"; fi
	@echo ""
	@echo "-- NAT gateways (region-wide check: $(REGION)) --"
	@nats=$$(aws ec2 describe-nat-gateways --region $(REGION) \
		--filter "Name=state,Values=pending,available,deleting" \
		--query 'NatGateways[].NatGatewayId' --output text 2>/dev/null); \
	if [ -z "$$nats" ]; then echo "PASS: no NAT gateways in $(REGION)"; \
	else echo "FAIL: NAT gateways present -> $$nats"; fi
	@echo ""
	@echo "Note: load balancer / NAT checks are region-wide, not tag-scoped — assumes"
	@echo "this is run against a dedicated sandbox account/region for this project."

cost: ## Print the hourly/daily/monthly burn-rate estimate for this config
	@echo "eks-platform — estimated burn rate (ap-south-1, current variables.tf defaults)"
	@echo ""
	@printf "%-34s %10s %10s %14s\n" "Resource" "Hourly" "Daily" "Monthly(~730h)"
	@printf "%-34s %10s %10s %14s\n" "--------" "------" "-----" "--------------"
	@printf "%-34s %10s %10s %14s\n" "EKS control plane (flat, no free tier)" "\$$0.100" "\$$2.40" "\$$73.00"
	@printf "%-34s %10s %10s %14s\n" "t3.small SPOT nodes x2" "~\$$0.014" "~\$$0.34" "~\$$10.66"
	@printf "%-34s %10s %10s %14s\n" "EBS gp3 20GiB root volumes x2" "~\$$0.005" "~\$$0.12" "~\$$3.65"
	@printf "%-34s %10s %10s %14s\n" "Public IPv4 addresses x2" "\$$0.010" "\$$0.24" "\$$7.30"
	@printf "%-34s %10s %10s %14s\n" "NAT Gateway (disabled)" "\$$0.000" "\$$0.00" "\$$0.00"
	@printf "%-34s %10s %10s %14s\n" "S3 state + DynamoDB lock" "~\$$0.000" "~\$$0.00" "<\$$0.05"
	@printf "%-34s %10s %10s %14s\n" "--------" "------" "-----" "--------------"
	@printf "%-34s %10s %10s %14s\n" "TOTAL (applied, idle)" "~\$$0.13" "~\$$3.10" "~\$$94.60"
	@echo ""
	@echo "Spot/EBS figures are estimates — actual spot price varies by AZ and time."
	@echo "Full breakdown, assumptions, and the 'forgot to destroy' scenario: docs/COST.md"
