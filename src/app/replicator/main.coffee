async = require 'async'
ChangeDispatcher = require './change/change_dispatcher'
Db = require '../lib/database'
DesignDocuments = require './design_documents'
DeviceStatus = require '../lib/device_status'
FilterManager = require './filter_manager'
fs = require './filesystem'
ReplicationLauncher = require "./replication_launcher"

log = require('../lib/persistent_log')
    prefix: "replicator main"
    date: true


#Replicator extends Model to watch/set inBackup, inSync
module.exports = class Replicator extends Backbone.Model

    db: null
    config: null

    # backup images functions are in replicator_backups
    _.extend Replicator.prototype, require './replicator_backups'

    _.extend Replicator.prototype, require '../migrations/replicator_migration'

    defaults: ->
        inSync: false
        inBackup: false


    initFileSystem: (callback) ->
        fs.initialize (err, downloads, cache) =>
            return callback err if err
            @downloads = downloads
            @cache = cache
            callback()


    initConfig: (@config, @requestCozy, @database) ->
        @db = @database.replicateDb
        @photosDB = @database.localDb


    # pings the cozy to check the credentials without creating a device
    checkCredentials: (url, password, callback) ->
        options =
            url: "#{url}/login"
            auth: false
            send:
                username: 'owner'
                password: password
        window.app.init.requestCozy.post options, (err, res) ->
            if err and err.message is "Unexpected token <"
                error = t err.message
            else if err
                # Unexpected error, just show it to the user.
                log.error err
                error = err.message
                if error.indexOf('CORS request rejected') isnt -1
                    error = t 'connexion error'
            else if response?.status is 0
                error = t 'connexion error'
            else if response?.statusCode isnt 200
                error = err?.message or body.error or body.message
            else
                error = null

            callback error

    registerRemoteSafe: (url, password, deviceName, callback, num = 0) ->
        name = deviceName
        name += "-#{num}" if num > 0
        log.debug 'deviceName', name
        @_registerRemote url, password, name, (err, body) =>
            if err and err.message is 'device name already exist'
                console.info 'The above 400 is totally normal. Device name \
                    already exist, we test another'
                @registerRemoteSafe url, password, deviceName, callback, num + 1
            else
                callback err, body

    _registerRemote: (url, password, deviceName, callback) ->
        options =
            url: "#{url}/device"
            auth:
                username: 'owner'
                password: password
            send:
                login: deviceName
                permissions: @config.get 'devicePermissions'
        @requestCozy.post options, (err, res) ->
            if res.status is 401 and response.reason
                callback new Error 'cozy need patch'
            else if res.status is 401
                callback new Error 'wrong password'
            else if res.status is 400
                callback new Error 'device name already exist'
            else if res.status isnt 201
                log.error "while registering device:  #{response.statusCode}"
                callback new Error response.statusCode, response.reason
            else
                callback err, res.body


    updatePermissions: (password, callback) ->
        options =
            url: "#{@config.getCozyUrl()}/device/#{@config.get('deviceName')}"
            auth:
                username: 'owner'
                password: password
            send:
                login: @config.get 'deviceName'
                permissions: app.init.config.getDefaultPermissions()
        @requestCozy.put options, (err, response, body) =>
            return callback err if err

            @config.set 'devicePermissions', body.permissions, callback


    takeCheckpoint: (callback) ->
        path = '/_changes?descending=true&limit=1'
        options =
            url: @requestCozy.getReplicationUrl path
        @requestCozy.get options, (err, res) ->
            return callback err if err
            window.app.checkpointed = res.body.last_seq
            callback()


    # Fetch all documents, with a previously put couchdb view.
    _fetchAll: (doc, callback) ->
        options =
            url: @requestCozy.getDataSystemUrl "/request/#{doc.docType}/all/"
            send:
                include_docs: true
                show_revs: true
        @requestCozy.post options, (err, res) ->
            if not err and res.status isnt 200
                err = new Error res.status, res.reason

            return callback err if err
            callback null, res.body


    # 1. Fetch all documents of specified docType
    # 2. Put in PouchDB
    # 2.1 : optionnaly, fetch attachments before putting in pouchDB
    # Return the list of added doc to PouchDB.
    copyView: (options, callback) ->
        log.info "enter copyView for #{options.docType}."
        # Last step
        putInPouch = (doc, cb) =>
            @db.put doc, 'new_edits':false, (err) ->
                return cb err if err
                cb null, doc

        # 1. Fetch all documents
        retryOptions =
            times: options.retry or 1
            interval: 20 * 1000

        async.retry retryOptions, ((cb) => @_fetchAll options, cb)
        , (err, rows) =>
            return callback null unless rows?.length isnt 0

            # 2. Put in PouchDB
            async.mapSeries rows, (row, cb) =>
                doc = row.doc

                # 2.1 Fetch attachment if needed (typically contact docType)
                if options.attachments is true and doc._attachments?
                # TODO? needed : .picture?
                    path = "/#{doc._id}?attachments=true"
                    requestOptions =
                        url: @requestCozy.getReplicationUrl path
                    @requestCozy.get requestOptions, (err, res) ->
                        # Continue on error (we just miss the avatar in case
                        # of contacts)
                        unless err
                            doc = res.body

                        putInPouch doc, cb

                else # No attachments
                    putInPouch doc, cb

            , callback


    # update index for further speeds up.
    updateIndex: (callback) ->
        log.debug "updateIndex"

        count = 0
        call = ->
            count++
            if count is 2
                callback()

        # build pouch's map indexes
        @db.query DesignDocuments.FILES_AND_FOLDER, {}, call

        # build pouch's map indexes
        @db.query DesignDocuments.LOCAL_PATH, {}, call

# END initialisations methods

# BEGIN Cache methods

    # Return the conventionnal name of the in filesystem folder for the
    # specified file.
    # @param file a cozy file document.
    _fileToEntryName: (file) ->
        # todo : fix bug when file not have binary
        return file.binary.file.id + '-' + file.binary.file.rev

    # Check if any version of the file is present in cache.
    # @param file a cozy file document.
    # @return true if any version of the file is present
    fileInFileSystem: (file) =>
        if file.docType.toLowerCase() is 'file'
            return @cache.some (entry) ->
                entry.name.indexOf(file.binary.file.id) isnt -1

    # Check if the file, with the specified version, is present in file system
    # @param file a cozy file document.
    # @return true if the file with the expected version is present
    fileVersion: (file) =>
        if file.docType.toLowerCase() is 'file'
            @cache.some (entry) =>
                entry.name is @_fileToEntryName file

    # Check if the all the subtree of the specified path is in cache.
    # @param path the path to the subtree to check
    # @param callback get true as result if the whole subtree is present.
    folderInFileSystem: (path, callback) =>
        options =
            startkey: path
            endkey: path + '\uffff'

        fsCacheFolder = @cache.map (entry) -> entry.name

        @db.query DesignDocuments.PATH_TO_BINARY, options, (err, results) ->
            return callback err if err
            return callback null, null if results.rows.length is 0
            callback null, _.every results.rows, (row) ->
                row.value in fsCacheFolder


    # Remove specified entry from @cache.
    # @param entry an entry of the @cache to remove.
    _removeFromCacheList: (entryName) ->
        for currentEntry, index in @cache when currentEntry.name is entryName
            @cache.splice index, 1
            break



    # Download the binary of the specified file in cache.
    # @param model cozy File document
    # @param progressback progress callback.
    getBinary: (model, progressback, callback) ->
        log.debug "getBinary"

        fs.getOrCreateSubFolder @downloads, @_fileToEntryName(model)
        , (err, binfolder) =>
            if err and err.code isnt FileError.PATH_EXISTS_ERR
                return callback err
            unless model.name
                return callback new Error 'no model name :' +
                        JSON.stringify(model)
            fileName = encodeURIComponent model.name
            fs.getFile binfolder, fileName, (err, entry) =>
                return callback null, entry.toURL() if entry

                # getFile failed, let's download
                path = "/data/#{model._id}/binaries/file"
                options = @requestCozy.getDataSystemOption path, true
                options.path = binfolder.toURL() + fileName
                log.info "download binary of #{model.name}"
                fs.download options, progressback, (err, entry) =>
                    # TODO : Is it reachable code ? http://git.io/v08Ap
                    # TODO changing the message ! ?
                    if err?.message? and
                    err.message is "This file isnt available offline" and
                    @fileInFileSystem model
                        for entry in cache
                            if entry.name.indexOf(binary_id) isnt -1
                                path = entry.toURL() + fileName
                                return callback null

                        return callback err
                    else if err
                        # failed to download
                        fs.delete binfolder, (delerr) ->
                            #@TODO handle delerr
                            callback err
                    else
                        @cache.push binfolder
                        callback null, entry.toURL()
                        @_removeAllLocal model, ->


    # Remove all versions in saved locally of the specified file-id, except the
    # specified rev.
    _removeAllLocal: (file, callback) ->
        async.eachSeries @cache, (entry, cb) =>
            if entry.name.indexOf(file.binary.file.id) isnt -1 and \
                    entry.name isnt @_fileToEntryName(file)
                fs.getDirectory @downloads, entry.name, (err, binfolder) =>
                    return cb err if err
                    fs.rmrf binfolder, (err) =>
                        @_removeFromCacheList entry.name
                        cb()
            else
                cb()
        , callback


    # Download recursively all files in the specified folder.
    # @param folder cozy folder document of the subtree's root
    # @param progressback progress callback
    getBinaryFolder: (folder, progressback, callback) ->
        @_getDbFilesOfFolder folder, (err, files) =>
            return callback err if err

            totalSize = files.reduce ((sum, file) -> sum + file.size), 0

            fs.freeSpace (err, available) =>
                return callback err if err
                if totalSize > available * 1024 # available is in KB
                    log.warn 'not enough space'
                    alert t 'not enough space'
                    callback null

                else
                    progressHandlers = {}
                    reportProgress = (id, done, total) ->
                        progressHandlers[id] = [done, total]
                        total = done = 0
                        for key, status of progressHandlers
                            done += status[0]
                            total += status[1]
                        progressback done, total

                    async.eachLimit files, 5, (file, cb) =>
                        pb = reportProgress.bind null, file._id
                        @getBinary file, pb, cb
                    , callback


    # Find all files in (recursively) the specified folder.
    # @param folder cozy folder document of the subtree's root
    _getDbFilesOfFolder: (folder, callback) ->
        path = folder.path
        path += '/' + folder.name
        options =
            startkey: [path]
            endkey: [path + '/\uffff', {}]
            include_docs: true

        @db.query DesignDocuments.FILES_AND_FOLDER, options, (err, results) ->
            return callback err if err
            docs = results.rows.map (row) -> row.doc
            files = docs.filter (doc) -> doc.docType?.toLowerCase() is 'file'

            callback null, files


    # Remove from cache specified file.
    # @param file a cozy file document.
    removeLocal: (file, callback) ->
        log.info "remove #{file.name} from cache."

        fs.getDirectory @downloads, @_fileToEntryName(file), (err, binfolder) =>
            return callback err if err
            fs.rmrf binfolder, (err) =>
                @_removeFromCacheList @_fileToEntryName(file)
                callback err


    removeLocalFolder: (folder, callback) ->
        @_getDbFilesOfFolder folder, (err, files) =>
            return callback err if err

            async.eachSeries files, (file, cb) =>
                @removeLocal file, cb
            , callback


    # wrapper around startRealtime to maintain the state of inSync
    sync: (options, callback) ->
        return callback() if @get 'inSync'

        log.info "start a sync"
        @set 'inSync', true
        options.live = false
        @startRealtime options, (err) =>
            @set 'inSync', false
            if err?.status is 404
                console.info 'The above 404 is not normal, but we retest with \
                              smallest pouch last_seq (remoteCheckpoint).'

                @checkpointLoop ?= 0
                @checkpointLoop++

                if @checkpointLoop > 10
                    return callback()
                else
                    options.remoteCheckpoint--
                    return @sync options, callback

            callback err


    ###*
     * Start real time replication
    ###
    startRealtime: (options = live: true, callback = ->) =>
        log.info "startRealtime, #{JSON.stringify options}"

        @stopRealtime() if @replicationLauncher

        @filterManager ?= new FilterManager @config, @requestCozy, @db

        @filterManager.filterRemoteExist =>
            @replicationLauncher = new ReplicationLauncher @database, \
                app.router, @filterManager.getFilterName(), @config
            @replicationLauncher.start options, (err) =>
                log.warn err if err
                @stopRealtime()
                callback.apply @, arguments

    # Stop replication.
    stopRealtime: =>
        log.info "stopRealtime"

        @replicationLauncher?.stop()
        delete @replicationLauncher

    # Update cache files with outdated revisions. Called while backup<
    syncCache:  (callback) ->
        @set 'backup_step', 'files_sync'
        @set 'backup_step_done', null

        # TODO: Add optimizations on db.query : avoid include_docs on big list.
        options =
            keys: @cache.map (entry) -> return entry.name.split('-')[0]
            include_docs: true

        @db.query DesignDocuments.BY_BINARY_ID, options, (err, results) =>
            return callback err if err

            changeDispatcher = new ChangeDispatcher @config
            processed = 0
            @set 'backup_step', 'files_sync'
            @set 'backup_step_total', results.rows.length
            async.eachSeries results.rows, (row, cb) =>
                @set 'backup_step_done', processed++
                changeDispatcher.dispatch row.doc, cb
            , callback

