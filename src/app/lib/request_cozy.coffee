request = require 'superagent'
log = require('./persistent_log')
    prefix: "RequestCozy"
    date: true


class RequestCozy


    constructor: (@config) ->


    get: (options, callback) ->
        req = request.get options.url
        @send req, options, callback


    post: (options, callback) ->
        req = request.post options.url
        @send req, options, callback


    put: (options, callback) ->
        req = request.put options.url
        @send req, options, callback


    send: (req, options, callback) ->
        req = @setAuth req, options
        req = req.send options.send if options.send
        req.end callback


    setAuth: (req, options) ->
        return req if options.auth is false

        if auth = options.auth
            username = auth.username
            password = auth.password
        else
            username = @config.get 'deviceName'
            password = @config.get 'devicePassword'

        req.auth username, password


    getReplicationUrl: (path) ->
        "#{@config.get 'cozyURL'}/replication#{path}"


    getDataSystemUrl: (path, withUrlAuth) ->
        if withUrlAuth
            url = @config.getCozyUrl()
        else
            url = @config.get 'cozyURL'
        "#{url}/ds-api#{path}"


    getDataSystemOption: (path, withUrlAuth) ->
        json: true
        auth:
            username: @config.get 'deviceName'
            password: @config.get 'devicePassword'
        url: @getDataSystemUrl path, withUrlAuth


module.exports = RequestCozy
