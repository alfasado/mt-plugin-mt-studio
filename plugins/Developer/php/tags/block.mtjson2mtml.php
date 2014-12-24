<?php
define( 'DataAPIVersion', 'v1' );
define( 'DataAPICacheDir', '/tmp' );
define( 'DataAPICacheTtl', '600' );
// /mt-data-api.json?api=%2fsites%2f2%2fentries%3fsortOrder%3dascend
function smarty_block_mtjson2mtml( $args, $content, &$ctx, &$repeat ) {
    $localvars = array( 'json2mtmlitems', 'json2mtmltotalsize',
                        'json2mtmlcounter' );
    $mt = $ctx->mt;
    if (! isset( $content ) ) {
        $ctx->localize( $localvars );
        if ( isset( $args[ 'items' ] ) ) {
            $item = $args[ 'item' ];
        } else {
            $item = 'items';
        }
        if ( isset( $args[ 'version' ] ) ) {
            $api_version = $args[ 'version' ];
        } else {
            $api_version = $mt->config( 'DataAPIVersion' ) ?
                           $mt->config( 'DataAPIVersion' ) : DataAPIVersion;
        }
        if ( isset( $args[ 'instance' ] ) ) {
            $instance_url = $args[ 'instance' ];
        } else {
            $instance_url = $mt->config( 'DataAPIURL' );
        }
        $request = $args[ 'request' ];
        $api = "${instance_url}/${api_version}${request}";
        if ( isset( $args[ 'cache_ttl' ] ) ) {
            $cache_ttl = $args[ 'cache_ttl' ];
            if ( $cache_ttl == 'auto' ) {
                $cache_ttl = $mt->config( 'DataAPICacheTtl' ) ?
                             $mt->config( 'DataAPICacheTtl' ) : 600;
            }
            $cache_dir = $mt->config( 'DataAPICacheDir' ) ?
                         $mt->config( 'DataAPICacheDir' ) : DataAPICacheDir;
            if ( isset( $args[ 'updated_at' ] ) ) {
                $updated_at = $args[ 'updated_at' ];
            }
            $filename = md5( $api );
            if ( $updated_at ) {
                $filename = $updated_at . '.' . $filename;
            }
            $cache_file = $cache_dir . DIRECTORY_SEPARATOR . $filename;
            if ( file_exists( $cache_file ) ) {
                $mtime = filemtime( $cache_file );
                $time = time();
                if ( ( $time - $cache_ttl ) < $mtime ) {
                    $buf = file_get_contents( $cache_file );
                }
            }
        }
        if (! $buf ) {
            $curl = curl_init();
            curl_setopt( $curl, CURLOPT_URL, $api );
            curl_setopt( $curl, CURLOPT_RETURNTRANSFER, 1 );
            curl_setopt( $curl, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1 );
            $buf = curl_exec( $curl );
            if ( curl_errno( $curl ) ) {
                $repeat = FALSE;
                return '';
            }
            curl_close( $curl );
            if ( $cache_file ) {
                file_put_contents( $cache_file, $buf );
                $mtime = filemtime( $cache_file );
            }
        }
        if ( isset( $args[ 'raw_data' ] ) ) {
            $type = 'application/json';
            $length = strlen( $buf );
            if ( $mt->config( 'SendHTTPHeaderMethod' ) == 'echo' ) {
                $headers[] = "content-type: $type";
            } else {
                header( "content-type: $type" );
            }
            $last_modified = gmdate( "D, d M Y H:i:s", $mtime ) . ' GMT';
            $etag = '"' . md5( $last_modified ) . '"';
            if ( $mt->config( 'SendHTTPHeaderMethod' ) == 'echo' ) {
                $headers[] = "Last-Modified: $last_modified";
                $headers[] = "ETag: $etag";
            } else {
                header( "Last-Modified: $last_modified" );
                header( "ETag: $etag" );
            }
            if ( $mt->config( 'SendHTTPHeaderMethod' ) == 'echo' ) {
               $headers[] = "Content-Length: $length";
            } else {
               header( "Content-Length: $length" );
            }
            if ( isset( $headers ) ) {
                echo implode( "\n", $headers ) . "\n\n";
            }
            echo $buf;
            exit();
            $repeat = FALSE;
        }
        $json = json_decode( $buf, TRUE );
        if ( isset( $args[ 'debug' ] ) ) {
            echo '<pre>' . $api . ':';
            var_dump( $json );
            echo '</pre>';
        }
        if ( $error = $json[ 'error' ] ) {
            $ctx->__stash[ 'vars' ][ 'code' ] = $error[ 'code' ];
            $ctx->__stash[ 'vars' ][ 'message' ] = $error[ 'message' ];
        } else {
            $totalResults = $json[ 'totalResults' ];
            if ( $item ) {
                $json = $json[ $item ];
            }
            $total = count( $json );
            $ctx->stash( 'json2mtmlitems', $json );
            $ctx->stash( 'json2mtmltotalsize', $total );
            $ctx->stash( 'json2mtmltotalresults', $totalResults );
            $ctx->stash( 'json2mtmlcounter', 0 );
            $counter = 0;
        }
    } else {
        if ( isset( $args[ 'raw_data' ] ) ) {
            $repeat = FALSE;
            return '';
        }
        $totalResults = $ctx->stash( 'json2mtmltotalresults' );
        $json = $ctx->stash( 'json2mtmlitems' );
        $counter = $ctx->stash( 'json2mtmlcounter' );
        $total = $ctx->stash( 'json2mtmltotalsize' );
    }
    if ( $json ) {
        if ( $total ) {
            if ( $counter < $total ) {
                $obj = $json[ $counter ];
                if (! $counter ) {
                    $ctx->__stash[ 'vars' ][ '__first__' ] = 1;
                } else {
                    $ctx->__stash[ 'vars' ][ '__first__' ] = 0;
                }
                foreach ( $obj as $key => $value ) {
                    $ctx->__stash[ 'vars' ][ $key ] = $value;
                    $ctx->__stash[ 'vars' ][ strtolower( $key ) ] = $value;
                }
                $counter++;
                $ctx->__stash[ 'vars' ][ '__counter__' ]  = $counter;
                $ctx->__stash[ 'vars' ][ '__odd__' ]      = ( $counter % 2 ) == 1;
                $ctx->__stash[ 'vars' ][ '__even__' ]     = ( $counter % 2 ) == 0;
                $ctx->__stash[ 'vars' ][ 'totalresults' ] = $totalResults;
                $ctx->__stash[ 'vars' ][ 'totalResults' ] = $totalResults;
                if ( $total == $counter ) {
                    $ctx->__stash[ 'vars' ][ '__last__' ] = 1;
                }
                $repeat = TRUE;
            } else {
                $ctx->restore( $localvars );
                $repeat = FALSE;
            }
            $ctx->stash( 'json2mtmlcounter', $counter );
        }
    }
    return $content;
}
?>