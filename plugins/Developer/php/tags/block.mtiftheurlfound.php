<?php
function smarty_block_mtiftheurlfound ( $args, $content, &$ctx, &$repeat ) {
    $blog = $ctx->stash( 'blog' );
    if ( isset( $args[ 'blog_id' ] ) ) {
        $blog_id = $args[ 'blog_id' ];
        $blog = $ctx->mt->db()->fetch_blog( $blog_id );
        $ctx->stash( 'blog', $blog );
    }
    if ( isset( $blog ) ) {
        $ctx->stash( 'blog_id', $blog->id );
    }
    if ( isset( $args[ 'tag' ] ) ) {
        $tag = $args[ 'tag' ];
        $tag = str_replace( '<', '', $tag );
        $tag = str_replace( '>', '', $tag );
        $tag = preg_replace( '/^mt:?/i', '', $tag );
        if ( isset( $args[ 'tagmodifier' ] ) ) {
            $modifier = $args[ 'tagmodifier' ];
            $modifier = str_replace( '\\', '', $modifier );
            $modifiers = explode( ' ', $modifier );
            $largs = array();
            foreach ( $modifiers as $m ) {
                $lr = explode( '=' , $m );
                $l = $lr[ 0 ];
                $r = $lr[ 1 ];
                $r = preg_replace( '/^"(.*?)"$/', '$1', $r );
                $largs[ $l ] = $r;
            }
        } else {
            $largs = $args; // local arguments without 'tag' element
            unset( $largs[ 'tag' ] );
        }
        try {
            $url = $ctx->tag( $tag, $largs );
        } catch ( exception $e ) {
            $url = '';
        }
    } else {
        $url = $args[ 'url' ];
    }
    $secure = !empty( $_SERVER[ 'HTTPS' ]) && strtolower( $_SERVER[ 'HTTPS' ] ) !== 'off'
                /* || isset($_SERVER['SERVER_PORT']) && $_SERVER['SERVER_PORT'] == 443 */
              ? 's' : '';
    $base = "http{$secure}://{$_SERVER[ 'HTTP_HOST' ]}";
    $blog_id = $args[ 'blog_id' ];
    if ( $blog_id ) {
        $blog = $ctx->mt->db()->fetch_blog( $blog_id );
    } else {
        $blog = $ctx->stash( 'blog' );
        // $blog_id = $blog->id;
    }
    if ( $blog ) {
        $base = $blog->site_url();
        $base = preg_replace( "!/$!", '', $base );
    }
    $base_url = preg_quote( $base, '/' );
    if ( preg_match( "/^$base_url/", $url ) ) {
        // File Check.
        $base_path = $_SERVER[ 'DOCUMENT_ROOT' ];
        if ( $blog ) {
            $base_path = $blog->site_path();
            $base_path = preg_replace( "!/$!", '', $base_path );
            $base_path = preg_replace( "!\\$!", '', $base_path );
        }
        $file = preg_replace( "/^$base_url/", $base_path, $url );
        $index = $ctx->mt->config( 'IndexBasename' );
        if (! $index ) $index = 'index';
        if ( preg_match( '/\/$/', $file ) ) {
            $blog = $ctx->stash( 'blog' );
            $file_extension = 'html';
            if ( ( $blog ) && ( $blog->file_extension ) ) {
                $file_extension = $blog->file_extension;
            }
            $file .= $index . '.' . $file_extension;
        }
        if ( is_file( $file ) ) {
            if ( $args[ 'need_path' ] ) {
                $res = array( $file, $blog );
                return $res;
            }
            return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
        }
        if ( $args[ 'target_dynamic' ] ) {
            require_once 'class.mt_fileinfo.php';
            $file = $ctx->mt->db()->escape( $file );
            $where = "fileinfo_file_path='{$file}' AND fileinfo_virtual=1";
            $_finfo = new FileInfo;
            $data = $_finfo->Find( $where, FALSE, FALSE, array( 'limit' => 1 ) );
            if ( $data ) {
                if ( $args[ 'need_path' ] ) {
                    $res = array( $file, $blog );
                    return $res;
                }
                return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
            }
        }
        if ( $args[ 'need_path' ] ) {
            return;
        }
        return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
    }
    if ( $args[ 'need_path' ] ) {
        return;
    }
    if ( (! $args[ 'target_outlink' ] ) 
        && (! $ctx->mt->config( 'ForceTargetOutLink' ) ) ) {
        return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
    }
    if ( $ctx->stash( 'theURLExists:' . $url ) ) {
        return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
    }
    set_error_handler( '_mtiftheurlfound_error_handler' );
    $header = @get_headers( $url );
    if ( preg_match( '#^HTTP/.*\s+[200|302|304]+\s#i', $header[0] ) ) {
        $ctx->stash( 'theURLExists:' . $url, 1 );
        return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, TRUE );
    }
    return $ctx->_hdlr_if( $args, $content, $ctx, $repeat, FALSE );
}
function _mtiftheurlfound_error_handler() {}
?>