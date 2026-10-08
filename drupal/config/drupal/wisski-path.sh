# Login shells reset PATH in /etc/profile and drop the image ENV, so
# phpcs, phpstan, phpunit and the other Composer bins disappear for
# developer and in-container agents. Non-login shells already inherit
# ENV PATH="/opt/drupal/vendor/bin:…".
export PATH="/opt/drupal/vendor/bin:${PATH}"
