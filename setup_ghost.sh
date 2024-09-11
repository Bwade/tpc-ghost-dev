#!/bin/bash

# Variables for better management
DOMAIN="thatpaleochick.com"
EMAIL="bwade231@gmail.com"
GITHUB_USER="bwade"
THEME_NAME="tpc-ghost-theme"
SMTP_SECRET_ID="smtp/thatpaleochick"
SMTP_HOST="email-smtp.us-east-1.amazonaws.com"
BACKUP_PATH="/var/backups"
GHOST_PATH="/var/www/ghost"
NEW_USER="bwade"

# Update system packages
sudo apt update && sudo apt upgrade -y

# Install necessary dependencies
sudo apt install -y nginx certbot python3-certbot-nginx git fail2ban mailutils awscli jq

# Install Node.js (LTS version) and Ghost-CLI
curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g ghost-cli

# Setup directories for Ghost
sudo mkdir -p $GHOST_PATH
sudo chown $USER:$USER $GHOST_PATH
cd $GHOST_PATH

# Install Ghost CMS (using Lightsail's default database setup)
ghost install --url https://$DOMAIN --process systemd --no-prompt

# Add a new user for deployment purposes
sudo adduser --disabled-password --gecos "" $NEW_USER
sudo usermod -aG sudo $NEW_USER

# Grant user access to Ghost directory
sudo chown -R $NEW_USER:$NEW_USER $GHOST_PATH
sudo chmod -R 755 $GHOST_PATH

# Configure Nginx for SSL
sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN

# Automate SSL certificate renewal via cron job
echo "0 */12 * * * /usr/bin/certbot renew --quiet && sudo systemctl reload nginx" | sudo tee -a /etc/crontab > /dev/null

# Fail2ban configuration to secure SSH and Nginx
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Fail2ban rules for Nginx and SSH
echo "
[DEFAULT]
bantime = 600
findtime = 600
maxretry = 3

[sshd]
enabled = true

[nginx-http-auth]
enabled = true
" | sudo tee /etc/fail2ban/jail.local

sudo systemctl restart fail2ban

# Retrieve SMTP credentials from AWS Secrets Manager
SMTP_USERNAME=$(aws secretsmanager get-secret-value --secret-id $SMTP_SECRET_ID --query SecretString --output text | jq -r .smtp_username)
SMTP_PASSWORD=$(aws secretsmanager get-secret-value --secret-id $SMTP_SECRET_ID --query SecretString --output text | jq -r .smtp_password)

# Email setup using SMTP for Ghost with AWS SES
ghost config --mail smtp --mailservice SMTP --mailhost $SMTP_HOST --mailport 465 --mailsecure true --mailuser $SMTP_USERNAME --mailpass $SMTP_PASSWORD

# Security headers for Nginx
sudo bash -c "cat << 'EOF' > /etc/nginx/snippets/security-headers.conf
add_header X-Frame-Options \"SAMEORIGIN\" always;
add_header X-XSS-Protection \"1; mode=block\" always;
add_header X-Content-Type-Options \"nosniff\" always;
add_header Referrer-Policy \"no-referrer-when-downgrade\" always;
add_header Content-Security-Policy \"default-src https: data: 'unsafe-inline' 'unsafe-eval';\" always;
EOF"

sudo bash -c "cat << 'EOF' >> /etc/nginx/sites-available/ghost
include snippets/security-headers.conf;
EOF"

# Enable auto-updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Logging and error detection setup
sudo bash -c "cat << 'EOF' > /etc/logrotate.d/ghost
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        [ -s /run/nginx.pid ] && kill -USR1 \$(cat /run/nginx.pid)
    endscript
    prerotate
        # Email logs if errors found
        if grep -qi 'error' /var/log/nginx/error.log; then
            mail -s 'Ghost CMS Error Detected' $EMAIL < /var/log/nginx/error.log
        fi
    endscript
}
EOF"

# Setup cron job for automated backups (without DB credentials)
# You can later update the DB_USER and DB_PASS if needed from the Ghost config
echo "0 3 * * * mysqldump --defaults-extra-file=/root/.my.cnf $DB_NAME | gzip > $BACKUP_PATH/ghost_backup_\$(date +\%F).sql.gz" | sudo tee -a /etc/crontab > /dev/null

# Restart Nginx to apply changes
sudo systemctl restart nginx
