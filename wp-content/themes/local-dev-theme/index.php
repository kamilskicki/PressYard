<?php
/**
 * PressYard billboard theme for local development.
 */
?><!doctype html>
<html <?php language_attributes(); ?>>
<head>
  <meta charset="<?php bloginfo( 'charset' ); ?>">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?php bloginfo( 'name' ); ?></title>
  <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
  <main style="max-width: 1100px; margin: 0 auto; min-height: 100vh; display: grid; place-items: center; padding: 2rem;">
    <section style="width: 100%; background: rgba(255,250,241,0.92); border: 1px solid rgba(17,17,17,0.08); box-shadow: 0 24px 80px rgba(17,17,17,0.12); padding: clamp(1.5rem, 3vw, 3rem);">
      <p style="margin: 0 0 1rem; font: 700 0.78rem/1.2 monospace; letter-spacing: 0.18em; text-transform: uppercase; color: #db5c32;">PressYard Local Environment</p>
      <h1 style="margin: 0; max-width: 11ch; font-size: clamp(2.8rem, 7vw, 6rem); line-height: 0.92;"><?php bloginfo( 'name' ); ?></h1>
      <p style="max-width: 42rem; margin: 1.5rem 0 0; font-size: 1.05rem; line-height: 1.7;">
        Your WordPress stack is up. This theme is a temporary billboard so copied environments still look intentional before the real project theme is installed or activated.
      </p>
      <div style="display: grid; gap: 0.85rem; margin-top: 2rem; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr));">
        <div style="background: #ffffff; border-left: 4px solid #db5c32; padding: 1rem 1.1rem;">
          <strong>Fast Path</strong>
          <p style="margin: 0.4rem 0 0;">Drop project ZIPs into <code>packages/</code> and restart the stack.</p>
        </div>
        <div style="background: #ffffff; border-left: 4px solid #2e5bff; padding: 1rem 1.1rem;">
          <strong>Direct URL</strong>
          <p style="margin: 0.4rem 0 0;"><a href="<?php echo esc_url( home_url( '/' ) ); ?>"><?php echo esc_html( home_url( '/' ) ); ?></a></p>
        </div>
        <div style="background: #ffffff; border-left: 4px solid #111111; padding: 1rem 1.1rem;">
          <strong>Next Step</strong>
          <p style="margin: 0.4rem 0 0;">Activate the project theme when ready. Until then, the environment is healthy and ready for dev work.</p>
        </div>
      </div>
    </section>
  </main>
  <?php wp_footer(); ?>
</body>
</html>
