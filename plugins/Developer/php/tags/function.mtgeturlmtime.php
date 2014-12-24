<?php
function smarty_function_mtgeturlmtime ( $args, &$ctx ) {
    require_once( 'block.mtiftheurlfound.php' );
    $args[ 'need_path' ] = 1;
    $repeat = TRUE;
    $res = smarty_block_mtiftheurlfound( $args, '', $ctx, $repeat );
    if ( isset ( $res ) ) {
        $file = $res[ 0 ];
        $blog = $res[ 1 ];
        if ( is_file( $file ) ) {
            $mtime = filemtime( $file );
        }
    } else {
        $blog_id = $args[ 'blog_id' ];
        if ( $blog_id ) {
            $blog = $ctx->mt->db()->fetch_blog( $blog_id );
        } else {
            $blog = $ctx->stash( 'blog' );
        }
        $url = $args[ 'url' ];
        set_error_handler( '_mtgeturlmtime_error_handler' );
        $headers = @get_headers( $url );
        $mtime;
        if ( strpos( $headers[ 0 ], '200' ) != 0 ) {
            $ctx->stash( 'theURLExists:' . $url, 1 );
            foreach( $headers as $header ) {
                if ( strpos( $header, 'Last-Modified: ' ) === 0 ) {
                    $mtime = str_replace( 'Last-Modified: ', '', $header );
                    break;
                }
            }
            $mtime = strtotime( $mtime );
        }
    }
    if ( $mtime ) {
        require_once( 'MTUtil.php' );
        $ts = offset_time_list( $mtime, $blog );
        $mtime = sprintf("%04d%02d%02d%02d%02d%02d",
            $ts[ 5 ]+1900, $ts[ 4 ]+1, $ts[ 3 ], $ts[ 2 ], $ts[ 1 ], $ts[ 0 ] );
        $args[ 'ts' ] = $mtime;
        return $ctx->_hdlr_date( $args, $ctx );
    }
    return 0;
}
function _mtgeturlmtime_error_handler() {}

?>