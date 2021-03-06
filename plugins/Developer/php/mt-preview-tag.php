<?php
    $mt_root;
    if ( $_SERVER[ 'REQUEST_METHOD' ] != 'POST' ) {
        __developer_permission_denied();
    }
    if ( file_exists( 'mt-config.cgi' ) ) {
        $base = dirname( __FILE__ );
        $mt_root = 1;
    } else {
        $base = dirname( dirname( dirname( dirname( __FILE__ ) ) ) );
    }
    $mt_cfg = $base . DIRECTORY_SEPARATOR . 'mt-config.cgi';
    $php_lib = $base . DIRECTORY_SEPARATOR . 'php' . DIRECTORY_SEPARATOR. 'mt.php';
    include( $php_lib );
    $mt = MT::get_instance( NULL, $mt_cfg );
    $ctx =& $mt->context();
    $cookie = $_COOKIE[ 'mt_user' ];
    if (! $cookie ) {
        __developer_permission_denied();
    }
    if ( preg_match( '/^(.*?)::(.*?)::.*$/', $cookie, $match ) ) {
        $sessid = $match[ 2 ];
    } else {
        __developer_permission_denied();
    }
    require( 'class.mt_session.php' );
    $session = new Session;
    $session->Load( "session_id='${sessid}' AND session_kind='US'" );
    if ( is_object( $session ) ) {
        $start = $session->start;
        $ttl = $mt->config( 'UserSessionTimeout' );
        if (! $ttl ) $ttl = 14400;
        if ( ( $start + $ttl ) < time() ) {
            $session = NULL;
        }
    }
    if (! is_object( $session ) ) {
        __developer_permission_denied();
    }
    $magic_token = $_POST[ 'magic_token' ];
    if ( $magic_token != $session->session_id ) {
        __developer_permission_denied();
    }
    require_once( 'MTUtil.php' );
    $mt->init_plugins();
    if ( $mt_root ) {
        $plugin_dir = $base . DIRECTORY_SEPARATOR . 'plugins' . DIRECTORY_SEPARATOR
        . 'Developer' . DIRECTORY_SEPARATOR . 'php' . DIRECTORY_SEPARATOR . 'tags';
    } else {
        $plugin_dir = dirname( __FILE__ ) . DIRECTORY_SEPARATOR . 'tags';
    }
    if ( is_dir( $plugin_dir ) ) {
        $mt->load_plugin( $plugin_dir );
        $ctx->add_plugin_dir( $plugin_dir );
    }
    $dynamicmtml = $base . DIRECTORY_SEPARATOR . 'addons' . DIRECTORY_SEPARATOR . 'DynamicMTML.pack';
    if (! is_dir( $dynamicmtml ) ) {
        $dynamicmtml = $base . DIRECTORY_SEPARATOR . 'plugins' . DIRECTORY_SEPARATOR . 'DynamicMTML.pack';
    }
    if ( is_dir( $dynamicmtml ) ) {
        $dynamicmtml = $dynamicmtml . DIRECTORY_SEPARATOR . 'php' . DIRECTORY_SEPARATOR . 'tags';
        if ( is_dir( $dynamicmtml ) ) {
            $mt->load_plugin( $dynamicmtml );
            $ctx->add_plugin_dir( $dynamicmtml );
        }
    }
    $tag = $_POST[ 'detail' ];
    $tagkind = $_POST[ 'tagkind' ];
    $tmpl = $_POST[ 'test_mtml' ];
    if ( get_magic_quotes_gpc() ) {
        $tmpl = stripslashes ( $tmpl );
    }
    $tag = strtolower( $tag );
    if ( strpos( $tag, 'mt' ) !== FALSE ) {
        $tag = preg_replace( '/^mt:{0,1}/', '', $tag );
    }
    $text_php = $_POST[ 'text_php' ];
    if ( get_magic_quotes_gpc() ) {
        $text_php = stripslashes ( $text_php );
    }
    $text_php =ltrim( $text_php );
    if ( preg_match( "/^function/", $text_php ) ) {
        $text_php = preg_replace(
        "/^function[^\{]{0,}/",
        "",
        $text_php );
        $text_php = ltrim( $text_php, '{' );
        $text_php = rtrim( $text_php );
        $text_php = rtrim( $text_php, '}' );
    }
    if ( $tagkind == 'block' ) {
        $ctx->add_container_tag( $tag, 'smarty_block_developer_preview' );
    } elseif ( $tagkind == 'conditional' ) {
        $ctx->add_conditional_tag( $tag, 'smarty_block_developer_preview' );
    } elseif ( $tagkind == 'function' ) {
        $ctx->add_tag( $tag, 'smarty_function_developer_preview' );
    } elseif ( $tagkind == 'modifier' ) {
        $ctx->stash( 'smarty_modifier_developer_preview', $text_php );
        $ctx->add_global_filter( $tag, 'smarty_modifier_developer_preview' );
    }
    $code = $text_php;
    $ctx->stash( 'developer_preview_tag', $code );
    require_once( 'MTUtil.php' );
    require_once( 'modifier.mteval.php' );
    $contents = smarty_modifier_mteval( $tmpl, TRUE );
    echo $contents;
    function smarty_block_developer_preview ( $args, $content, &$ctx, &$repeat ) {
        $code = $ctx->stash( 'developer_preview_tag' );
        return eval( $code );
    }
    function smarty_function_developer_preview ( $args, &$ctx ) {
        $code = $ctx->stash( 'developer_preview_tag' );
        return eval( $code );
    }
    function smarty_modifier_developer_preview ( $text, $arg ) {
        $mt = MT::get_instance();
        $ctx =& $mt->context();
        $code = $ctx->stash( 'smarty_modifier_developer_preview' );
        return eval( $code );
    }
    function __developer_permission_denied() {
        echo 'Permission denied.';
        exit();
    }
?>