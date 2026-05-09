#!/usr/bin/env python3
"""
Flask server for ResolveURL using libresolveurl
"""
# ik this is shit code but idk why its work so...

try:
    import re
    import os
    from typing import Optional
    import logging

    from flask import Flask, request, jsonify
    from urllib.parse import unquote

    # Setup config directories BEFORE importing libresolveurl
    base_dir = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    data_dir = os.path.join(base_dir, "python_data")

    print(f"DEBUG: base_dir={base_dir}, data_dir={data_dir}")

    # Create directories if they don't exist
    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(os.path.join(data_dir, "resources"), exist_ok=True)

    print("DEBUG: Directories created")

    # Set environment variables BEFORE importing libresolveurl
    os.environ.setdefault("LIBRESOLVEURL_CONFIG_DIR", data_dir)
    os.environ.setdefault("LIBRESOLVEURL_ADDON_PATH", data_dir)

    # Also patch the common module config before import
    import sys
    sys.path.insert(0, data_dir)
    
    # Add local LibResolveURL to path
    lib_resolve_url_path = os.path.join(os.path.dirname(__file__), "LibResolveURL")
    if os.path.exists(lib_resolve_url_path):
        print(f"DEBUG: Adding LibResolveURL path: {lib_resolve_url_path}")
        sys.path.insert(0, lib_resolve_url_path)
    else:
        print(f"DEBUG: LibResolveURL path not found: {lib_resolve_url_path}")

    print("DEBUG: About to import libresolveurl")


    try:
        import libresolveurl
        print("DEBUG: libresolveurl imported")

        # Patch resolveurl.common.settings_file to use our data_dir
        try:
            import resolveurl.common as common
            settings_dir = os.path.join(data_dir, "resources")
            os.makedirs(settings_dir, exist_ok=True)
            common.settings_file = os.path.join(settings_dir, "settings.xml")
            print("DEBUG: resolveurl.common patched")
            
            # Patch the Net class to disable SSL verification
            try:
                from resolveurl.lib import net
                original_net_init = net.Net.__init__
                
                def patched_net_init(self, *args, **kwargs):
                    kwargs['ssl_verify'] = False
                    original_net_init(self, *args, **kwargs)
                
                net.Net.__init__ = patched_net_init
                print("DEBUG: Net class patched for SSL verification bypass")
            except Exception as e:
                print(f"DEBUG: Could not patch Net class: {e}")
            
        except Exception as e:
            print(f"DEBUG: Could not patch resolveurl.common: {e}")
        
        LIBRESOLVEURL_AVAILABLE = True
    except ImportError as e:
        print(f"DEBUG: LibResolveURL not available: {e}")
        LIBRESOLVEURL_AVAILABLE = False
        libresolveurl = None


    # Configure logging
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    logger = logging.getLogger(__name__)

    # Flask app
    app = Flask(__name__)

    print("DEBUG: Flask app created")

    def host_name(url: str) -> str:
        """Extract host name from URL"""
        m = re.search(r'://(?:www\.)?([^/]+)', url)
        return m.group(1).split('.')[0].upper() if m else 'UNKNOWN'

    def resolve_url(url: str) -> Optional[str]:
        """Resolve a video URL using libresolveurl"""
        if LIBRESOLVEURL_AVAILABLE and libresolveurl:
            try:
                import ssl
                import urllib.request
                # Force SSL bypass before EVERY resolve call
                ctx = ssl.create_default_context()
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
                https_handler = urllib.request.HTTPSHandler(context=ctx)
                opener = urllib.request.build_opener(https_handler)
                urllib.request.install_opener(opener)
                
                result = libresolveurl.resolve(url)
                return result if result else None
            except Exception as e:
                print(f"DEBUG: Error resolving URL {url}: {e}")
                return None
        else:
            print(f"DEBUG: LibResolveURL not available, returning original URL")
            return None

    @app.route('/resolve', methods=['POST'])
    def resolve():
        """Resolve multiple video URLs"""
        try:
            data = request.get_json()
            print(f"DEBUG: Received data type: {type(data)}, data: {data}")
            
            # Handle both list and dict formats
            if isinstance(data, list):
                links = data
            elif isinstance(data, dict):
                links = data.get('links', [])
            else:
                return jsonify({'error': f'Unexpected data type: {type(data)}'}), 400
            
            results = []
            for item in links:
                try:
                    print(f"DEBUG: Processing item type: {type(item)}, item: {item}")
                    if isinstance(item, str):
                        # If item is just a URL string
                        url = item
                        headers = {'Referer': url}
                    elif isinstance(item, dict):
                        url = item.get('url')
                        language = item.get('language')
                        quality = item.get('quality')
                        if not url:
                            continue
                        headers = {'Referer': url}
                        if item.get('headers'):
                            headers.update(item['headers'])
                    else:
                        continue
                        
                    # Resolve URL
                    resolved = resolve_url(url)
                    
                    if resolved:
                        # Handle URLs with appended headers from ResolveURL
                        if '|' in resolved:
                            resolved_url, header_str = resolved.split('|', 1)
                            for pair in header_str.split('&'):
                                if '=' in pair:
                                    k, v = pair.split('=', 1)
                                    headers[k] = unquote(v)
                            resolved = resolved_url
                    
                        results.append({
                            'host': host_name(url),
                            'url': resolved,
                            'headers': headers,
                            'language': language,
                            'quality': quality
                        })
                except Exception as e:
                    print(f"DEBUG: Error processing item {item}: {e}")
                    continue
                
            return jsonify(results)
        except Exception as e:
            logger.error(f"Error in resolve: {e}")
            import traceback
            traceback.print_exc()
            return jsonify({'error': str(e)}), 500

    @app.route('/health', methods=['GET'])
    def health():
        """Health check endpoint"""
        return jsonify({'status': 'ok'})

    print("DEBUG: Routes defined")

except Exception as e:
    print(f"DEBUG: FATAL ERROR during setup: {e}")
    import traceback
    print(traceback.format_exc())
    import sys
    sys.stdout.flush()
    sys.exit(1)

print("DEBUG: Starting Flask server...")
import sys
sys.stdout.flush()

try:
    print("ResolveURL server starting on http://0.0.0.0:8080")
    sys.stdout.flush()
    
    # Run Flask server - this will block
    print("Running Flask app.run()...")
    sys.stdout.flush()
    app.run(host="0.0.0.0", port=8080, debug=False, use_reloader=False, threaded=True)
    
except Exception as e:
    print(f"FATAL ERROR in app.run: {e}")
    import traceback
    print(traceback.format_exc())
    sys.stdout.flush()
