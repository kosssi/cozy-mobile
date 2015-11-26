exports.config =

    # See docs at http://brunch.readthedocs.org/en/latest/config.html.

    paths:
        public:  '../www'
        test: 'test'

    plugins:
        coffeelint:
            options:
                indentation: value: 4, level: 'error'

    conventions:
        vendor:  /(vendor)|(tests)(\/|\\)/ # do not wrap tests in modules

    files:
        javascripts:
            joinTo:
                'javascripts/app.js': /^app/
                'javascripts/vendor.js': [
                    'bower_components/jquery/jquery.js'
                    'bower_components/underscore/underscore.js'
                    'bower_components/backbone/backbone.js'
                    'bower_components/async/lib/async.js'
                    'bower_components/ionic/release/js/ionic.js'
                    'bower_components/polyglot/lib/polyglot.js'
                    'bower_components/pouchdb/dist/pouchdb.js'
                    'bower_components/pouchdb-quick-search/dist/pouchdb.quick-search.js'
                ]
            order:
                # Files in `vendor` directories are compiled before other files
                # even if they aren't specified in order.
                before: [
                    'bower_components/jquery/jquery.js'
                    'bower_components/underscore/underscore.js'
                    'bower_components/backbone/backbone.js'
                ]

        stylesheets:
            joinTo: 'stylesheets/app.css'

        templates:
            defaultExtension: 'jade'
            joinTo: 'javascripts/app.js'
