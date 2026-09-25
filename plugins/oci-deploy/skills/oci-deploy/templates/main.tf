# Providers + backend + module calls.
#
# Skill scaffolding rules:
#   - Always include the OCI provider + the `module "core"` block.
#   - Only include the providers/required_providers/module blocks for addons
#     the user actually opted into (cloudflare, auth0, github). If a feature
#     wasn't requested, delete the matching block entirely — DO NOT leave
#     stubs. That's the whole point of the addon-module architecture.
#   - Substitute PROJECT_NAME and the optional backend bucket/namespace/key
#     with project-specific values.

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 9.3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.9.0"
    }

    # Add only when the cloudflare addon is invoked below:
    # cloudflare = { source = "cloudflare/cloudflare", version = ">= 5.0.0" }
    # tls        = { source = "hashicorp/tls",         version = ">= 4.4.0" }

    # Add only when the auth0 addon is invoked below:
    # auth0 = { source = "auth0/auth0", version = ">= 1.58.0" }

    # Add only when the github addon is invoked below:
    # github = { source = "integrations/github", version = ">= 6.13.0" }
  }

  # Optional remote state in OCI Object Storage.
  # Create the bucket once, then uncomment.
  # backend "oci" {
  #   bucket    = "terraform-state"
  #   namespace = "YOUR_OS_NAMESPACE"
  #   key       = "PROJECT_NAME/terraform.tfstate"
  # }
}

provider "oci" {
  tenancy_ocid = var.TENANCY_OCID
  user_ocid    = var.USER_OCID
  fingerprint  = var.FINGERPRINT
  private_key  = local.oci_private_key
  region       = var.REGION
}

# Add only when the cloudflare addon is invoked below.
# provider "cloudflare" {
#   api_token = var.CLOUDFLARE_API_TOKEN
# }

# Add only when the auth0 addon is invoked below.
# provider "auth0" {
#   domain        = var.AUTH0_DOMAIN
#   client_id     = var.AUTH0_M2M_CLIENT_ID
#   client_secret = var.AUTH0_M2M_CLIENT_SECRET
# }

# Add only when the github addon is invoked below.
# provider "github" {
#   owner = var.GITHUB_OWNER
#   token = var.GITHUB_TOKEN
# }

# --- Core infrastructure (always) ---

module "core" {
  source = "github.com/MMJLee/terraform-oci-free-tier"

  tenancy_ocid   = var.TENANCY_OCID
  region         = var.REGION
  ssh_public_key = local.ssh_public_key
  project_name   = "PROJECT_NAME"

  # Adjust shape — total OCPUs must be <= 4 and total memory <= 24GB
  instances = {
    app = {
      ocpus           = 4
      memory_gb       = 24
      block_volume_gb = 50
      extra_packages  = []
      behind_lb       = true # set to false if not invoking the cloudflare addon
    }
  }

  # 0, 1, or 2 ATP databases. Remove keys you don't need.
  databases = {
    main = { display_name = "MainDB", db_name = "MAINDB" }
  }

  bucket_name = "PROJECT_NAME-backups"
}

# --- Cloudflare addon (only if user wants LB + DNS + origin SSL) ---
# Wire vcn_id, public_subnet_id, instance_private_ips from module.core.
# Filter `instances` to those with behind_lb = true.
# module "cloudflare" {
#   source = "github.com/MMJLee/terraform-oci-free-tier//modules/cloudflare"
#
#   tenancy_ocid     = var.TENANCY_OCID
#   project_name     = "PROJECT_NAME"
#   vcn_id           = module.core.vcn_id
#   public_subnet_id = module.core.public_subnet_id
#
#   instances = {
#     app = { app_port = 8080, behind_lb = true }
#   }
#   instance_private_ips = { for k, v in module.core.instances : k => v.private_ip }
#
#   domain_name        = var.DOMAIN_NAME
#   cloudflare_zone_id = var.CLOUDFLARE_ZONE_ID
#   dns_records        = [var.DOMAIN_NAME, "app"]
# }

# --- Auth0 addon (only if user wants SPA/M2M + post-login JWT action) ---
# module "auth0" {
#   source = "github.com/MMJLee/terraform-oci-free-tier//modules/auth0"
#
#   auth0_api_audience  = var.AUTH0_API_AUDIENCE
#   auth0_jwt_namespace = var.AUTH0_JWT_NAMESPACE
#   auth0_callback_urls = var.AUTH0_CALLBACK_URLS
#   auth0_admin_user_id = var.AUTH0_ADMIN_USER_ID
# }

# --- GitHub Actions secret sync addon (only if user wants CI/CD secrets pushed) ---
# Auto-syncs: OCI auth, SSH keys, Cloudflare creds (if those vars are set),
# Auth0 creds (if those vars are set), per-instance <NAME>_IP, per-database
# <KEY>_DB_OCID, vault, OS namespace. Pass `extra_secrets` for additional
# project-specific values.
# module "github_secrets" {
#   source = "github.com/MMJLee/terraform-oci-free-tier//modules/github"
#
#   github_owner = var.GITHUB_OWNER
#   github_repo  = var.GITHUB_REPO
#
#   # OCI auth (synced as secrets)
#   oci_user_ocid   = var.USER_OCID
#   oci_fingerprint = var.FINGERPRINT
#   oci_private_key = local.oci_private_key
#   ssh_private_key = local.ssh_private_key
#   ssh_public_key  = local.ssh_public_key
#   ip_address      = var.IP_ADDRESS
#
#   # Cloudflare creds (only set if cloudflare addon is also enabled)
#   # cloudflare_api_token = var.CLOUDFLARE_API_TOKEN
#   # cloudflare_zone_id   = var.CLOUDFLARE_ZONE_ID
#   # domain_name          = var.DOMAIN_NAME
#
#   # Auth0 creds (only set if auth0 addon is also enabled)
#   # auth0_domain            = var.AUTH0_DOMAIN
#   # auth0_client_id         = var.AUTH0_CLIENT_ID
#   # auth0_client_secret     = var.AUTH0_CLIENT_SECRET
#   # auth0_m2m_client_id     = var.AUTH0_M2M_CLIENT_ID
#   # auth0_m2m_client_secret = var.AUTH0_M2M_CLIENT_SECRET
#
#   # Module-derived values (always passed)
#   tenancy_ocid          = var.TENANCY_OCID
#   region                = var.REGION
#   vault_ocid            = module.core.vault_id
#   vault_key_id          = module.core.vault_key_id
#   vault_crypto_endpoint = module.core.vault_crypto_endpoint
#   os_namespace          = module.core.os_namespace
#   instance_public_ips   = { for k, v in module.core.instances : k => v.public_ip }
#   database_ids          = module.core.database_ids
#
#   # Project-specific extras (merged on top of the auto-derived secrets)
#   extra_secrets = {
#     # GOOGLE_CLIENT_ID = var.GOOGLE_CLIENT_ID
#   }
# }
