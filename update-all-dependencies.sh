#!/bin/bash

# Update Helm dependencies for all services
services=("file-storage-service" "notification-service" "trip-service" "audit-service" "user-service" "social-service" "moderation-service" "keycloak" "tenant-service" "reporting-service")

echo "Updating Helm dependencies for all services..."

for service in "${services[@]}"; do
  echo "→ Updating $service..."
  cd "$service"
  helm dependency update
  cd ..
  echo "✓ $service updated"
  echo ""
done

echo "All dependencies updated successfully!"
