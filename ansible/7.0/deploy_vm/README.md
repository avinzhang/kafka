# Deploy EC2 instances with terraform
  * Run terraform to deploy
    * Init
    ```
    terraform init
    ```

    * Plan
    ```
    terraform plan -var-file=ansible.tfvars
    ```

    * Apply
    ```
    terraform apply --auto-approve -var-file=ansible.tfvars
    ```

  * Run two scripts to setup internal and external DNS mapping

  * Update /etc/hosts for all instances for DNS mapping


