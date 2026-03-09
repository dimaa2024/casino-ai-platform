provider "google" {
  project = var.organization_context.bootstrap_project
  region  = var.organization_context.default_region
}

module "property_cell" {
  for_each = var.properties

  source = "../../modules/property_cell"

  property = each.value
  organization_context = {
    labels = var.organization_context.labels
  }
}
