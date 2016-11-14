Raven = require 'raven'


instance = null


module.exports = class Sentry


    constructor: ->
        return instance if instance
        instance = @

        @domain = 'sentry.fafaru.com'
        @port = '8080'
        @key = '639aedf9a8374012a976fd51237b436a'
        @project = '2'


    getSentryUrl: ->
        "http://#{@key}@#{@domain}:#{@port}/#{@project}"


    initialize: (@config) ->
        if @config?.isSentryLog()
            release = {release: @config.get 'appVersion'}
            @raven = Raven.config(@getSentryUrl(), release).install()


    capture: (msg, level) ->
        if @config?.isSentryLog()
            @raven.captureMessage msg, { level: level }