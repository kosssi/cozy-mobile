PictureHandler = require './picture_handler'
fs = require '../../replicator/filesystem'
DeviceStatus = require '../device_status'
ConnectionHandler = require '../connection_handler'
log = require('../persistent_log')
    prefix: 'MediaUploader'
    date: true


instance = null


module.exports = class MediaUploader


    constructor: (@pictureHandler) ->
        return instance if instance
        instance = @

        @pictureHandler ?= new PictureHandler @
        @config ?= app.init.config
        @requestCozy ?= app.init.requestCozy
        @connectionHandler = new ConnectionHandler()


    upload: (callback) ->
        @isUploadable (ok) =>
            if ok
                @pictureHandler.upload callback
            else
                callback()


    checkBinary: (binaryId, callback) ->
        options =
            method: 'get'
            type: 'data-system'
            path: "/data/exist/#{binaryId}"
            retry: 3

        @requestCozy.request options, (err, res, body) ->
            return callback err if err
            callback null, body.exist


    uploadBinary: (file, fileId, callback) ->
        log.debug "uploadBinary"

        path = "/data/#{fileId}/binaries/"

        url = @requestCozy.getDataSystemUrl path
        data = new FormData()
        data.append 'file', file, 'file'
        $.ajax
            type: 'POST'
            url: url
            headers:
                'Authorization': 'Basic ' +
                    btoa(@config.get('deviceName') + ':' +
                            @config.get('devicePassword'))
            username: @config.get 'deviceName'
            password: @config.get 'devicePassword'
            data: data
            contentType: false
            processData: false
            success: (success) -> callback null, success
            error: callback


    createFile: (picture, localPath, cozyPath, callback) ->
        log.debug "createFile"

        fileClassFromMime = (type) ->
            switch type.split('/')[0]
                when 'image' then "image"
                when 'audio' then "music"
                when 'video' then "video"
                when 'text', 'application' then "document"
                else "file"

        create = (mimetype, size) =>
            date = moment picture.creationDate, "YYYY-MM-DD HH:mm a z"

            dbFile =
                docType          : 'File'
                localPath        : localPath
                name             : picture.filename
                path             : cozyPath
                class            : fileClassFromMime mimetype
                mime             : mimetype
                lastModification : date.toISOString()
                creationDate     : date.toISOString()
                size             : size
                tags             : ['from-' + @config.get 'deviceName']

            @_sendFileOrFolder dbFile, callback

        if device.platform is "Android"
            create picture.mimetype, picture.size
        else
            cordova.plugins.photoLibrary.getPhoto picture, (blob) =>
                create blob.type, blob.size
            , callback


    createFolder: (name, path, callback) ->
        log.debug "createFolder"

        dbFolder =
            docType          : 'Folder'
            name             : name
            path             : path
            lastModification : new Date().toISOString()
            creationDate     : new Date().toISOString()
            tags             : ['from-' + @config.get 'deviceName']

        @_sendFileOrFolder dbFolder, callback


    _sendFileOrFolder: (doc, callback) ->
        options =
            method: 'post'
            type: 'data-system'
            path: '/data'
            body: doc
            retry: 3

        @requestCozy.request options, (err, result, body) ->
            return callback err if err

            unless result.status is 201
                log.debug result
                return callback new Error "Status code is not 201."

            callback null, body._id


    isUploadable: (callback) ->
        return callback false unless @config.get 'syncImages'
        if not @connectionHandler.isWifi() and @config.get 'syncOnWifi'
            return callback false
        DeviceStatus.checkReadyForSync (err, ready, msg) ->
            callback ready
