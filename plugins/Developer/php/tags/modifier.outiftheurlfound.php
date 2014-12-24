<?php
function smarty_modifier_outiftheurlfound( $text, $url ) {
    if (! preg_match( '!^https{0,1}://!', $url ) ) {
        if ( preg_match( '!"(https{0,1}://.*?)"!', $text, $matches ) ) {
            $url = $matches[ 1 ];
        } else if ( preg_match( "!'(https{0,1}://.*?)'!", $text, $matches ) ) {
            $url = $matches[ 1 ];
        }
        if (! $url ) return '';
    }
    $mt = MT::get_instance();
    $ctx = $mt->context();
    $args = array();
    require_once( 'block.mtiftheurlfound.php' );
    $args[ 'need_path' ] = 1;
    $args[ 'target_dynamic' ] = 1;
    $repeat = TRUE;
    $res = smarty_block_mtiftheurlfound( $args, '', $ctx, $repeat );
    if ( isset ( $res ) ) {
        return $text;
    } else {
        if ( $ctx->stash( 'theURLExists:' . $url ) ) {
            return $text;
        }
        if ( $mt->config( 'ForceTargetOutLink' ) ) {
            set_error_handler( '_outiftheurlfound_error_handler' );
            $headers = @get_headers( $url );
            if ( strpos( $headers[ 0 ], '200' ) != 0 ) {
                $ctx->stash( 'theURLExists:' . $url, 1 );
                return $text;
            }
        }
    }
    return '';
}
function _outiftheurlfound_error_handler() {}

?>