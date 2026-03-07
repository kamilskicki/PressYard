FROM wordpress:php8.2-apache

RUN pecl install xdebug \
  && docker-php-ext-enable xdebug \
  && rm -rf /tmp/pear

COPY docker/wordpress-xdebug/xdebug.ini /usr/local/etc/php/conf.d/zz-xdebug.ini
