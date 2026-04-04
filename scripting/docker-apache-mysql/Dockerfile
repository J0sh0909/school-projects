FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt update -y && \
    apt install iputils-ping -y && \
    apt install isc-dhcp-client -y && \
    apt-get install -y --no-install-recommends \
        apache2 \
        openssl \
        lynx \
        php \
        libapache2-mod-php \
        php-mysql && \
    echo "ServerName localhost" >> /etc/apache2/apache2.conf && \
    rm -rf /var/lib/apt/lists/*
RUN a2enmod ssl && \
    mkdir -p /etc/apache2/ssl && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/apache2/ssl/apache.key \
        -out /etc/apache2/ssl/apache.crt \
        -subj "/C=CA/ST=QC/L=Montreal/O=Lab/CN=localhost" && \
    cat > /etc/apache2/sites-available/ssl.conf <<'EOF'
<VirtualHost *:443>
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl/apache.crt
    SSLCertificateKeyFile /etc/apache2/ssl/apache.key
    ServerName localhost
</VirtualHost>
EOF
RUN a2ensite ssl.conf
RUN echo "<?php \
\$conn = new mysqli('serveur_mysql', getenv('MYSQL_USER'), getenv('MYSQL_PASSWORD'), 'ma_db_web'); \
if (\$conn->connect_error) { die('Connection failed: ' . \$conn->connect_error); } \
\$result = \$conn->query('SELECT * FROM noms'); \
while(\$row = \$result->fetch_assoc()) { echo \$row['nom'] . '<br>'; } \
\$conn->close(); \
?>" > /var/www/html/index.php
RUN rm -f /var/www/html/index.html
EXPOSE 443
CMD ["apache2ctl", "-D", "FOREGROUND"]
