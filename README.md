# WordPress Deployment on Kubernetes with Azure MySQL and Cert-Manager

This repository contains Kubernetes manifests for deploying a highly available WordPress application. The setup includes an Azure MySQL Flexible Server for the database, persistent storage using Azure Files, NGINX Ingress for traffic management, and Cert-Manager for automatic SSL/TLS certificates from Let's Encrypt. It also includes a PowerShell script to automate the provisioning of the necessary Azure infrastructure and a Dockerfile for building the custom WordPress image.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [File Descriptions](#file-descriptions)
- [Infrastructure Deployment](#infrastructure-deployment)
- [Kubernetes Deployment Steps](#kubernetes-deployment-steps)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

## Overview

This deployment leverages the following Kubernetes components and Azure services:

-   **WordPress Pods:** Multiple replicas for high availability.
-   **Azure Database for MySQL Flexible Server:** External managed database for WordPress.
-   **Azure Files:** Persistent storage for WordPress `wp-content` directory, enabling shared access across multiple pods.
-   **NGINX Ingress Controller:** Manages external access to the WordPress service.
-   **Cert-Manager:** Automates the provisioning and management of TLS certificates from Let's Encrypt.
-   **Kubernetes Secrets:** Securely stores database credentials and WordPress authentication salts.
-   **Kubernetes ConfigMap:** Provides custom PHP configurations for WordPress.
-   **Azure PowerShell Script (`resource-deployment.ps1`):** Automates the creation of Azure resources like Resource Group, Virtual Network, Subnets, Azure MySQL Flexible Server, Azure Kubernetes Service (AKS) Cluster, and Azure Container Registry (ACR).
-   **Dockerfile:** Defines the custom WordPress image used in the deployment.

## Prerequisites

Before deploying, ensure you have the following:

1.  **Azure Subscription:** An active Azure subscription.
2.  **Azure CLI:** Installed and configured for your Azure subscription.
3.  **Azure PowerShell:** Installed and configured (for running `resource-deployment.ps1`).
4.  **Docker:** Installed for building the WordPress image.
5.  **`kubectl`:** Configured to connect to your Kubernetes cluster.


## File Descriptions

-   `resource-deployment.ps1`:
    A PowerShell script to automate the provisioning of Azure infrastructure. This includes:
    -   Creation of a Resource Group.
    -   Creation of a Virtual Network (VNet) with dedicated subnets for AKS and MySQL Private Endpoint.
    -   Deployment of an Azure Database for MySQL Flexible Server with a private endpoint.
    -   Deployment of an Azure Kubernetes Service (AKS) cluster integrated with the VNet.
    -   Creation of an Azure Container Registry (ACR).
    -   Assignment of `AcrPull` role to the AKS cluster's managed identity for image pulling.
    -   Builds and pushes the custom WordPress Docker image to ACR.

-   `Dockerfile`:
    Defines the custom Docker image for WordPress. It is based on the official `wordpress:latest` image and sets the working directory, exposes port 80, and defines the command to start the Apache web server. This custom image is used by the `wordpress-deployment.yaml`.

-   `cluster-issuer.yaml`:
    Defines a `ClusterIssuer` resource for `cert-manager` to obtain SSL/TLS certificates from Let's Encrypt using the HTTP-01 challenge. This is crucial for enabling HTTPS for your WordPress site.

-   `mysql-azure-secret.yaml`:
    Contains two Kubernetes `Secret` resources:
    -   `wordpress-azure-mysql-secret`: Stores sensitive connection details for your Azure MySQL Flexible Server (host, username, password, database name). **IMPORTANT: Update these values with your actual Azure MySQL details after the infrastructure is deployed.**
    -   `wordpress-auth-secret`: Stores WordPress authentication unique keys and salts. **IMPORTANT: Generate new salts from `https://api.wordpress.org/secret-key/1.1/salt/` and update these values.**

-   `wordpress-config-map.yml`:
    Defines a `ConfigMap` named `php-config` that contains custom PHP settings (e.g., `upload_max_filesize`, `memory_limit`, `max_execution_time`) for the WordPress pods.

-   `wordpress-deployment.yaml`:
    Defines the Kubernetes `Deployment` for the WordPress application.
    -   It creates 3 replicas of the WordPress pod.
    -   Includes an `initContainer` to fix permissions on the `wp-content` directory, ensuring proper ownership for the `www-data` user.
    -   Mounts the `wordpress-persistent-storage` PVC to `/var/www/html/wp-content`.
    -   Mounts the `php-config` ConfigMap as `custom.ini` in the PHP configuration directory.
    -   Injects database credentials and WordPress salts as environment variables from the respective secrets.
    -   Sets various WordPress-specific environment variables for debugging and performance.

-   `wordpress-files-pvc.yaml`:
    Defines a `StorageClass` and a `PersistentVolumeClaim` (PVC) for WordPress.
    -   `StorageClass` `azurefile-wordpress`: Configures Azure Files as the provisioner, allowing `ReadWriteMany` access mode, which is essential for multiple WordPress pods to share the same `wp-content` directory.
    -   `PersistentVolumeClaim` `wordpress-content-pvc`: Requests 5Gi of storage for the `wp-content` directory.

-   `wordpress-ingress.yaml`:
    Defines the Kubernetes `Ingress` resource.
    -   Configures NGINX Ingress to route external traffic to the `wordpress-service`.
    -   Uses `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation to automatically provision a TLS certificate for `blog.bigfirm.online`.
    -   Enforces SSL redirection.
    -   Sets proxy timeouts and body size limits.

-   `wordpress-service.yaml`:
    Defines a Kubernetes `Service` of type `ClusterIP` for the WordPress deployment. This service exposes port 80 internally within the cluster, allowing the Ingress controller to forward traffic to the WordPress pods.

## Infrastructure Deployment

This section outlines how to provision the necessary Azure infrastructure using the provided PowerShell script.

1.  **Review and Customize `resource-deployment.ps1`:**
    Open `resource-deployment.ps1` and review the variables at the top of the script. Customize values such as `$RESOURCE_GROUP_NAME`, `$LOCATION`, `$MYSQL_ADMIN_PASSWORD`, `$AKS_CLUSTER_NAME`, and `$ACR_NAME` to match your desired setup. **Ensure you set a strong password for `$MYSQL_ADMIN_PASSWORD`**.

2.  **Login to Azure:**
    ```powershell
    az login
    ```

3.  **Execute the PowerShell Script:**
    Navigate to the directory containing `resource-deployment.ps1` in your PowerShell terminal and run:
    ```powershell
    .\resource-deployment.ps1
    ```
    This script will:
    -   Create the Azure Resource Group, VNet, and Subnets.
    -   Deploy the Azure MySQL Flexible Server and its private DNS zone link.
    -   Deploy the AKS cluster.
    -   Create the Azure Container Registry.
    -   Build your WordPress Docker image (using the provided `Dockerfile`) and push it to the ACR.
    -   Assign the necessary permissions for AKS to pull images from ACR.
    -   Get AKS credentials and create the `wordpress` and `cert-manager` namespaces.

## Kubernetes Deployment Steps

Once your Azure infrastructure is provisioned by `resource-deployment.ps1`, follow these steps to deploy WordPress to your Kubernetes cluster:

1.  **Update Secrets and install cert manager and nginx controller:**
    After `resource-deployment.ps1` completes, it will output the MySQL FQDN. Use this, along with the admin user, password, and database name you configured in the script, to update `mysql-azure-secret.yaml`.
    Also, generate new WordPress salts from `https://api.wordpress.org/secret-key/1.1/salt/` and update the `wordpress-auth-secret` section in `mysql-azure-secret.yaml`.
    Install Nginx ingress controller and certificate manager
     ```bash
    
     helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
     helm repo update
     helm install nginx-ingress ingress-nginx/ingress-nginx `
    --namespace ingress-nginx --create-namespace `
    --set controller.replicaCount=1 `
    --set controller.service.type=LoadBalancer `
    --set controller.service.externalTrafficPolicy=Local `
    --set controller.admissionWebhooks.enabled=false
     kubectl create namespace cert-manager
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install `
      cert-manager jetstack/cert-manager `
      --namespace cert-manager `
      --version v1.18.1 `
      --set installCRDs=true        
    ```
    Get Nginx public IP (External IP) and add it to DNS registar:
    ```bash
    kubectl get services -n ingress-nginx
    ```
    

3.  **Apply Secrets and ConfigMap:**
    ```bash
    kubectl apply -f mysql-azure-secret.yaml -n wordpress
    kubectl apply -f wordpress-config-map.yml -n wordpress
    ```

4.  **Apply Persistent Storage:**
    ```bash
    kubectl apply -f wordpress-files-pvc.yaml -n wordpress
    ```

5.  **Apply WordPress Deployment and Service:**
    ```bash
    kubectl apply -f wordpress-service.yaml -n wordpress
    kubectl apply -f wordpress-deployment.yaml -n wordpress
    ```

6.  **Apply Cert-Manager ClusterIssuer (if not already applied):**
    ```bash
    kubectl apply -f cluster-issuer.yaml
    ```
    *Note: The `ClusterIssuer` is a cluster-scoped resource, so it doesn't need a namespace.*

7.  **Apply Ingress:**
    Before applying the Ingress, ensure that the domain `blog.bigfirm.online` (or your chosen domain) points to the external IP address of your NGINX Ingress Controller.
    ```bash
    kubectl apply -f wordpress-ingress.yaml -n wordpress
    ```

8.  **Verify Deployment:**
    Check the status of your pods, services, and ingress:
    ```bash
    kubectl get pods -n wordpress
    kubectl get svc -n wordpress
    kubectl get ingress -n wordpress
    kubectl get certificate -n wordpress # To check cert-manager status
    ```

## Configuration

-   **Azure Infrastructure:** Modify variables in `resource-deployment.ps1`.
-   **Dockerfile:** Ensure the `Dockerfile` is in the same directory as `resource-deployment.ps1` for image building.
-   **Database Connection:** Modify `mysql-azure-secret.yaml` after infrastructure deployment.
-   **WordPress Salts:** Update `mysql-azure-secret.yaml` with fresh salts.
-   **PHP Configuration:** Adjust `wordpress-config-map.yml` for custom PHP settings.
-   **WordPress Image:** The `resource-deployment.ps1` script builds and pushes `myregistry2025azurecr.azurecr.io/custom-wordpress:v1`. If you change the image name in `wordpress-deployment.yaml`, ensure it matches what's pushed to ACR.
-   **Resource Limits:** Adjust `resources` in `wordpress-deployment.yaml` based on your expected load.
-   **Storage Size:** Modify `storage: 5Gi` in `wordpress-files-pvc.yaml` if you need more or less storage for `wp-content`.
-   **Domain Name:** Update `hosts` and `rules.host` in `wordpress-ingress.yaml` to your desired domain.
-   **Cert-Manager Email:** Update `email` in `cluster-issuer.yaml` to your contact email for Let's Encrypt.

## Troubleshooting

-   **Infrastructure Deployment Issues (`resource-deployment.ps1`):**
    -   Check the PowerShell console output for any error messages during script execution.
    -   Ensure you have the necessary Azure permissions to create resources.
    -   Verify that Azure CLI and Azure PowerShell are correctly installed and authenticated.

-   **Pods not running:**
    -   Check pod logs: `kubectl logs <pod-name> -n wordpress`
    -   Describe pod events: `kubectl describe pod <pod-name> -n wordpress`
    -   Ensure secrets are correctly applied and values are base64 encoded if not using `stringData`.
    -   Verify the custom WordPress image is accessible from your cluster (check ACR permissions for AKS).

-   **Ingress not working / SSL issues:**
    -   Check Ingress events: `kubectl describe ingress wordpress-ingress -n wordpress`
    -   Check Cert-Manager `Certificate` and `CertificateRequest` resources: `kubectl get certificate -n wordpress` and `kubectl describe certificate <certificate-name> -n wordpress`
    -   Ensure your DNS record for `blog.bigfirm.online` points to the Ingress controller's external IP.
    -   Verify NGINX Ingress Controller is running correctly.

-   **Persistent Volume Claim issues:**
    -   Check PVC status: `kubectl get pvc -n wordpress`
    -   Describe PVC events: `kubectl describe pvc wordpress-content-pvc -n wordpress`
    -   Ensure Azure Files CSI driver is installed and configured in your AKS cluster.
