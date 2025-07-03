FROM wordpress:latest

# Define the working directory for WordPress (usually /var/www/html in official images)
WORKDIR /var/www/html

# Expose port 80 for the web server
EXPOSE 80

# Command to start Apache (default for official WordPress image)
CMD ["apache2-foreground"]
