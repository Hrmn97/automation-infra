resource "mongodbatlas_cluster" "cluster-vpc-peer" {
  project_id                                      = var.ATLAS_PROJECT_ID
  name                                            = "mongo-cluster-${var.environment}"
  num_shards                                      = 1
  replication_factor                              = var.mongodb_replication_factor
  cloud_backup                                    = true
  auto_scaling_disk_gb_enabled                    = true
  mongo_db_major_version                          = "8.0"
  provider_name                                   = var.ATLAS_PROVIDER
  disk_size_gb                                    = 20
  provider_volume_type                            = "STANDARD"
  provider_instance_size_name                     = var.environment == "prod" ? "M30" : "M10"
  provider_region_name                            = var.atlas_region
  auto_scaling_compute_enabled                    = var.environment == "prod" ? true : false
  provider_auto_scaling_compute_max_instance_size = var.environment == "prod" ? "M40" : null
  provider_auto_scaling_compute_min_instance_size = var.environment == "prod" ? "M30" : null
  lifecycle { ignore_changes = [provider_instance_size_name] }
}