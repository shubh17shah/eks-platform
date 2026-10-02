# tflint config, shared by both Terraform roots (terraform/ and bootstrap/)
# via `tflint --config <repo-root>/.tflint.hcl --chdir <root>` — see
# .github/workflows/terraform-ci.yml and `make lint`.
#
# Scope is deliberately narrow: catch real mistakes (deprecated syntax,
# unused declarations, AWS-specific misconfigurations) without turning CI
# red over style tflint and `terraform fmt` already disagree on.

plugin "aws" {
  enabled = true
  version = "0.35.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  plugin_dir = "~/.tflint.d/plugins"
}

# --- Terraform language rules (bundled, no plugin needed) ------------------

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_standard_module_structure" {
  # Both roots here are single-purpose stacks, not reusable modules
  # (no modules/ subdirectory is expected) — this rule checks for a
  # modules/ layout that doesn't apply to either root.
  enabled = false
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_workspace_remote" {
  enabled = true
}

# --- AWS ruleset rules -------------------------------------------------
#
# No extra `rule` blocks needed here: the `plugin "aws"` block above already
# turns on the ruleset's full set of default-enabled checks (invalid
# instance types, invalid regions/AZs, deprecated resource arguments, etc.)
# against actual AWS API schemas — that's most of the value of this plugin,
# and it requires no per-rule configuration.
#
# Deliberately NOT enabling `aws_resource_missing_tags`: terraform/'s
# provider block sets `default_tags` (terraform/providers.tf) so every
# resource in that root gets `Project`/`ManagedBy`/`Owner` automatically,
# without repeating `tags = var.tags` on each one — a style this specific
# rule doesn't account for consistently across tflint versions. Enforcing
# it here risks fighting a deliberate tagging strategy, not catching a bug.
