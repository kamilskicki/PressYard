<?php
/**
 * Plugin Name: PressYard Mailpit
 * Description: Routes wp_mail() to the local Mailpit inbox when enabled.
 */

declare(strict_types=1);

$mailpitEnabled = filter_var(getenv('PRESSYARD_ENABLE_MAILPIT') ?: '', FILTER_VALIDATE_BOOLEAN);
if (!$mailpitEnabled) {
    return;
}

add_action(
    'phpmailer_init',
    static function ($phpmailer): void {
        $phpmailer->isSMTP();
        $phpmailer->Host = getenv('PRESSYARD_MAILPIT_HOST') ?: 'mailpit';
        $phpmailer->Port = (int) (getenv('PRESSYARD_MAILPIT_PORT') ?: 1025);
        $phpmailer->SMTPAuth = false;
        $phpmailer->SMTPSecure = '';
        $phpmailer->SMTPAutoTLS = false;

        if (empty($phpmailer->From)) {
            $phpmailer->From = getenv('PRESSYARD_MAILPIT_FROM_EMAIL') ?: 'wordpress@pressyard.local';
        }

        if (empty($phpmailer->FromName)) {
            $phpmailer->FromName = getenv('PRESSYARD_MAILPIT_FROM_NAME') ?: 'PressYard';
        }
    }
);
