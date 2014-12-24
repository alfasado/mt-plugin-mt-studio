<?php
/*
<MTBuildLink tag="WebSiteURL" prefix="<li>" postfix="</li>" attribute='target="_blank"'
labelTag="WebSiteName" labelModifier='escape\="html"' IfTheUrlFound="1">

<MTBuildLink url="http://www.example.com/"
html='<li><a href="http://www.example.com/" target="_blank">Movable Type</a></li>'
IfTheUrlFound="1">
*/
function smarty_function_mtbuildlink ( $args, &$ctx ) {
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
            $largs = $args;
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
    if ( isset( $args[ 'labeltag' ] ) ) {
        $labeltag = $args[ 'labeltag' ];
        $labeltag = str_replace( '<', '', $labeltag );
        $labeltag = str_replace( '>', '', $labeltag );
        $labeltag = preg_replace( '/^mt:?/i', '', $labeltag );
        if ( isset( $args[ 'labelmodifier' ] ) ) {
            $modifier = $args[ 'labelmodifier' ];
            $modifier = str_replace( '\\', '', $modifier );
            $modifiers = explode( ' ', $modifier );
            $largs = $args;
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
            $label = $ctx->tag( $labeltag, $largs );
        } catch ( exception $e ) {
            $label = '';
        }
    }
    if (! $label ) {
        if ( isset( $args[ 'label' ] ) ) {
            $label = $args[ 'label' ];
        }
    }
    if (! $label ) $label = $url;
    if ( isset( $args[ 'iftheurlfound' ] ) ) {
        require_once( 'block.mtiftheurlfound.php' );
        $args[ 'need_path' ] = 1;
        $repeat = TRUE;
        $res = smarty_block_mtiftheurlfound( $args, '', $ctx, $repeat );
        $url_exists;
        if ( isset ( $res ) ) {
            $file = $res[ 0 ];
            $blog = $res[ 1 ];
            $ctx->stash( 'blog', $blog );
            $url_exists = TRUE;
        } else {
            if ( ( isset( $args[ 'target_outlink' ] ) )
                || ( $ctx->mt->config( 'ForceTargetOutLink' ) ) )  {
                if ( $ctx->stash( 'theURLExists:' . $url ) ) {
                    $url_exists = TRUE;
                } else {
                    $blog_id = $args[ 'blog_id' ];
                    if ( $blog_id ) {
                        $blog = $ctx->mt->db()->fetch_blog( $blog_id );
                    } else {
                        $blog = $ctx->stash( 'blog' );
                    }
                    set_error_handler( '_mtbuildlink_error_handler' );
                    $headers = @get_headers( $url );
                    if ( strpos( $headers[ 0 ], '200' ) != 0 ) {
                        $ctx->stash( 'theURLExists:' . $url, 1 );
                        $url_exists = TRUE;
                    }
                }
            }
        }
        if (! $url_exists ) {
            $url = '';
        }
    }
    if (! $url ) return '';
    if ( isset( $args[ 'html' ] ) ) {
        return $args[ 'html' ];
    }
    $link = '<a href="' . $url . '"';
    if ( isset( $args[ 'attribute' ] ) ) {
        $attribute = trim( $args[ 'attribute' ] );
        $link .= " ${attribute}";
    }
    $link .= ">${label}</a>";
    if ( isset( $args[ 'prefix' ] ) ) {
        $link = $args[ 'prefix' ] . $link;
    }
    if ( isset( $args[ 'postfix' ] ) ) {
        $link .= $args[ 'postfix' ];
    }
    return $link;
}
function _mtbuildlink_error_handler() {}

?>