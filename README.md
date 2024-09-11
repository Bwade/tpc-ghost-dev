# Ghost CMS Setup Script

This script is designed to automate the setup and configuration of a Ghost CMS instance on an AWS Lightsail server. It installs and configures key services, such as Nginx for serving your Ghost instance, SSL certificates for HTTPS, email via AWS SES, automated backups, and a deployment user for CI/CD integration with GitHub Actions.

## Script Overview

### Variables

The script uses several variables to improve management and organization:

- **DOMAIN**: The domain name for your Ghost site (e.g., `thatpaleochick.com`).
- **EMAIL**: Your email address for notifications (e.g., `bwade231@gmail.com`).
- **GITHUB_USER**: Your GitHub username (e.g., `bwade`).
- **THEME_NAME**: The name of the theme repository you want to deploy (e.g., `tpc-ghost-theme`).
- **SMTP_SECRET_ID**: The identifier for your SMTP credentials stored in AWS Secrets Manager (e.g., `smtp/thatpaleochick`).
- **SMTP_HOST**: The Amazon SES SMTP endpoint (e.g., `email-smtp.us-east-1.amazonaws.com`).
- **BACKUP_PATH**: Path to store database backups (e.g., `/var/backups`).
- **GHOST_PATH**: The path where Ghost will be installed (e.g., `/var/www/ghost`).
- **NEW_USER**: The name of the new user created for deployments (e.g., `bwade`).

---

## Detailed Breakdown of Script Sections

### 1. **System Update and Package Installation**

bash

Copy code

`sudo apt update && sudo apt upgrade -y sudo apt install -y nginx certbot python3-certbot-nginx git fail2ban mailutils awscli jq`

- **Updates the System**: Ensures your Lightsail instance has the latest security patches and software updates.
- **Installs Required Packages**:
    - **Nginx**: Web server to serve Ghost.
    - **Certbot**: Tool to request SSL certificates from Let’s Encrypt.
    - **Ghost-CLI**: Command-line tool to manage Ghost installations.
    - **Fail2ban**: A security tool to protect against brute force attacks.
    - **Mailutils**: Enables sending emails from the server.
    - **AWS CLI**: Used to interact with AWS services (Secrets Manager in this case).
    - **jq**: Used for parsing JSON responses from AWS Secrets Manager.

### 2. **Node.js and Ghost-CLI Installation**

bash

Copy code

`curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash - sudo apt install -y nodejs sudo npm install -g ghost-cli`

- Installs **Node.js** (required by Ghost) and **Ghost-CLI** (for Ghost installation and management).

### 3. **Ghost Directory Setup**

bash

Copy code

`sudo mkdir -p $GHOST_PATH sudo chown $USER:$USER $GHOST_PATH cd $GHOST_PATH`

- Creates and prepares the directory where Ghost will be installed.

### 4. **Ghost Installation**

bash

Copy code

`ghost install --url https://$DOMAIN --process systemd --no-prompt`

- Installs Ghost in the specified directory and configures it to use `systemd` for service management.
- **Domain**: Configures Ghost to use the provided domain (e.g., `https://thatpaleochick.com`).

### 5. **Create New User for Deployment**

bash

Copy code

`sudo adduser --disabled-password --gecos "" $NEW_USER sudo usermod -aG sudo $NEW_USER sudo chown -R $NEW_USER:$NEW_USER $GHOST_PATH sudo chmod -R 755 $GHOST_PATH`

- Creates a new user **bwade** for deployment purposes.
- **Permissions**: Grants `bwade` ownership of the Ghost installation directory so that it can be used for deploying updates.

### 6. **Configure SSL with Certbot**

bash

Copy code

`sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN`

- Uses Certbot to obtain SSL certificates from Let’s Encrypt, securing your domain with HTTPS.

### 7. **Automated SSL Renewal**

bash

Copy code

`echo "0 */12 * * * /usr/bin/certbot renew --quiet && sudo systemctl reload nginx" | sudo tee -a /etc/crontab > /dev/null`

- Schedules a **cron job** to automatically renew the SSL certificate every 12 hours and reload Nginx if the certificate is renewed.

### 8. **Fail2ban Security Setup**

bash

Copy code

`sudo systemctl enable fail2ban sudo systemctl start fail2ban`

- Enables and starts Fail2ban to protect your server from brute-force attacks.
- Configures rules for **SSH** and **Nginx** to protect against unauthorized login attempts and HTTP abuse.

### 9. **SMTP Email Configuration with AWS SES**

bash

Copy code

`SMTP_USERNAME=$(aws secretsmanager get-secret-value --secret-id $SMTP_SECRET_ID --query SecretString --output text | jq -r .smtp_username) SMTP_PASSWORD=$(aws secretsmanager get-secret-value --secret-id $SMTP_SECRET_ID --query SecretString --output text | jq -r .smtp_password)  ghost config --mail smtp --mailservice SMTP --mailhost $SMTP_HOST --mailport 465 --mailsecure true --mailuser $SMTP_USERNAME --mailpass $SMTP_PASSWORD`

- Retrieves **SMTP credentials** from AWS Secrets Manager securely (no plain-text storage of passwords).
- Configures Ghost to send emails via AWS SES for tasks like user signup, password resets, and notifications.

### 10. **Security Headers for Nginx**

bash

Copy code

`sudo bash -c "cat << 'EOF' > /etc/nginx/snippets/security-headers.conf add_header X-Frame-Options \"SAMEORIGIN\" always; add_header X-XSS-Protection \"1; mode=block\" always; add_header X-Content-Type-Options \"nosniff\" always; add_header Referrer-Policy \"no-referrer-when-downgrade\" always; add_header Content-Security-Policy \"default-src https: data: 'unsafe-inline' 'unsafe-eval';\" always; EOF"`

- Adds security headers to Nginx to protect against attacks like XSS and clickjacking.

### 11. **Enable Auto-Upgrades**

bash

Copy code

`sudo apt install -y unattended-upgrades sudo dpkg-reconfigure --priority=low unattended-upgrades`

- Enables **unattended-upgrades** to automatically apply security patches and updates to the server.

### 12. **Log Management and Error Detection**

bash

Copy code

`sudo bash -c "cat << 'EOF' > /etc/logrotate.d/ghost /var/log/nginx/*.log {     daily     missingok     rotate 14     compress     delaycompress     notifempty     create 0640 www-data adm     sharedscripts     postrotate         [ -s /run/nginx.pid ] && kill -USR1 \$(cat /run/nginx.pid)     endscript     prerotate         if grep -qi 'error' /var/log/nginx/error.log; then             mail -s 'Ghost CMS Error Detected' $EMAIL < /var/log/nginx/error.log         fi     endscript } EOF"`

- Configures **logrotate** to rotate and compress Nginx logs daily.
- Checks for **errors** in the Nginx logs, and if any are found, sends an email notification to the configured email address.

### 13. **Automated MySQL Backups**

bash

Copy code

`echo "0 3 * * * mysqldump --defaults-extra-file=/root/.my.cnf $DB_NAME | gzip > $BACKUP_PATH/ghost_backup_\$(date +\%F).sql.gz" | sudo tee -a /etc/crontab > /dev/null`

- Schedules a daily **cron job** to back up the MySQL database at 3 AM.
- The backup file is saved in the directory defined by `$BACKUP_PATH`.

---

## Post-Installation Steps

### SSH Key Setup for GitHub Actions

1. **Generate SSH Keys for `bwade`**: After the script runs, log in as `bwade` and generate an SSH key for deployment:

    bash

    Copy code

    `sudo -i -u bwade ssh-keygen -t rsa -b 4096 -C "your_email@example.com"`

2. **Add SSH Key to GitHub**:

    - Add the generated private key to your GitHub repository as a secret (`SSH_PRIVATE_KEY`).
    - Add the public key to the `~/.ssh/authorized_keys` file for `bwade` on your server.

### GitHub Actions Setup

1. Create a `.github/workflows/deploy.yml` file in your GitHub theme repository for automatic deployments.
2. Add the appropriate GitHub Actions workflow to deploy the theme to the server using the `bwade` user.

---

## Summary

This script automates the complete setup of a secure, production-ready Ghost CMS instance on AWS Lightsail. It includes SSL configuration, email setup via AWS SES, security enhancements, automated backups, and prepares a user for GitHub Actions-based CI/CD.