BaseView = require './layout/base_view'
DesignDocuments = require '../replicator/design_documents'
FileCacheHandler = require '../lib/file_cache_handler'
ChangeFolderHandler = require '../replicator/change/change_folder_handler'
ChangeFileHandler = require '../replicator/change/change_file_handler'
HeaderView = require './layout/header'
pathHelper = require '../lib/path'
mimetype = require '../lib/mimetype'


log = require('../lib/persistent_log')
    prefix: "FileViewer"
    date: true


module.exports = class FileViewer extends BaseView


    btnBackEnabled: true
    template: require '../templates/file_viewer'
    backExit: false
    append: true


    events: ->
        'swipe .collection-item': 'onSwipe'
        'click .menu': 'toggleMenu'
        'click .remove': 'removeFile'
        'click .download': 'downloadFile'
        'click .toggleSearch': 'toggleSearch'
        'click .goParent': 'goParent'


    getRenderData: ->
        path: @options.path
        loading: @loading
        files: @files
        parentPath: @parentPath
        folderName: @folderName
        breadcrumb: @breadcrumb


    initialize: ->
        super
        @fileCacheHandler = new FileCacheHandler()
        @router ?= app.router
        @loading = true
        @files = []
        @config ?= app.init.config

        @breadcrumb = @getBreadcrumb @options.path

        if @options.path isnt '/'
            @parentPath = pathHelper.getDirName @options.path
            @parentPath = '/' unless @parentPath
            @folderName = pathHelper.getFileName @options.path
        else
            @append = false
            @parentPath = ''
            @backExit = true

        startLoading = =>
            if @config.get 'firstSyncFiles'
                @load @options.path
            else
                setTimeout ->
                    startLoading()
                , 1000

        startLoading()
        @loadjQueryFunction = false

        app.view = @

        @changeFolderHandler = new ChangeFolderHandler()
        @changeFileHandler = new ChangeFileHandler()
        cb = (object, path) =>
            if @parentPath is path
                @update()
        @listenTo @changeFolderHandler, "change:path", cb
        @listenTo @changeFileHandler, "change:path", cb



    getBreadcrumb: (path) ->
        split = path.split '/'
        breadcrumb = []
        link = ''

        for name in split
            link += "/#{name}" if name
            breadcrumb.push
                link: link
                name: name

        breadcrumb


    downloadFile: (event) ->
        if $(event.currentTarget).hasClass 'collection-item'
            menu = $(event.currentTarget)

            return if menu.data('doctype').toLowerCase() is 'folder'
            return if menu.data('cached') is true
        else
            menu = $(event.currentTarget).parents '.menuOpen'

        cozyFileId = menu.data 'key'
        if @fileCacheHandler.cache[cozyFileId]
            return if menu.data('type') in ['file-image', 'file-music', 'file-video', 'file-chart', 'presentation-play', 'file-document']
            event.preventDefault()
            return @fileCacheHandler.open menu.data 'fullpath'

        event.preventDefault()
        @files.forEach (file) =>
            if file._id is cozyFileId
                progressDesign = menu.find('.fileProgress')
                reportProgress = (id, done, total) ->
                    percentage = parseInt done * 100 / total
                    progressDesign.css('width', percentage + '%')
                pregressBar = reportProgress.bind null, file._id
                menu.find('.progress').show()
                @fileCacheHandler.downloadBinary file, pregressBar, =>
                    file.isCached = true
                    menu.find('.progress').hide()
                    progressDesign.css('width', '0%')
                    @render()
                    if menu.data('type') in ['file-image', 'file-music', 'file-video', 'file-chart', 'presentation-play', 'file-document']
                        @router.navigate menu.attr('href'), trigger: true
                    else
                        @fileCacheHandler.open menu.data 'fullpath'


    removeFile: (event) ->
        event.preventDefault()

        cozyFileId = $(event.currentTarget).parents('.menuOpen').data 'key'
        @files.forEach (file) =>
            if file._id is cozyFileId
                @fileCacheHandler.removeLocal file, =>
                    file.isCached = false
                    @render()


    toggleMenu: (event) ->
        event.preventDefault()

        menu = $(event.currentTarget)
        collection = menu.parent()
        isOpen = collection.hasClass 'menuOpen'

        # close all menu
        $('.menuOpen').each (index) ->
            $(this).removeClass 'menuOpen'
            $(this).find('.menu').closeFAB()

        unless isOpen
            collection.toggleClass 'menuOpen'
            menu.openFAB()



    onSwipe: (event) ->
        console.log 'swipe'
        direction = event?.originalEvent?.gesture?.direction
        if direction is 'right'
            @goParent()


    goParent: ->
        window.location = "#folder#{@parentPath}" if @options.path isnt '/'


    load: (filePath) ->
        if @header
            @header.update path: filePath, displaySearch: true
        else
            @header = new HeaderView path: filePath

        if filePath is '/'
            @backExit = true
            filePath = ''

        if filePath is t 'photos'
            params =
                startkey: [filePath, {}]
                endkey: [filePath]
                descending: true
            view = DesignDocuments.PICTURES
        else
            params =
                startkey: [filePath]
                endkey: [filePath, {}]
            view = DesignDocuments.FILES_AND_FOLDER

        @replicateDb ?= app.init.database.replicateDb
        @replicateDb.query view, params, (err, results) =>
            inPathIds = results.rows.map (row) -> return row.id

            params =
                keys: inPathIds
                include_docs: true

            @replicateDb.allDocs params, (err, items) =>
                @files = items.rows.map (row) =>
                    doc = row.doc
                    doc.icon = mimetype.getIcon doc
                    doc.isCached = @fileCacheHandler.isCached doc
                    if doc.icon is 'folder'
                        doc.link = "#folder#{doc.path}/#{doc.name}"
                    else
                        base = @fileCacheHandler.downloads.nativeURL
                        doc.fullPath = "#{base}#{doc._id}/#{doc.name}"
                        doc.link = "#media/#{doc.mime}//#{doc.fullPath}"
                    return row.doc
                @loading = false
                @render()


    afterRender: ->
        breadcrumb = document.getElementById "breadcrumb"
        breadcrumb.scrollLeft = breadcrumb.scrollWidth if breadcrumb
        if @options.path isnt '/'
            @back = 0
            setTimeout =>
                element = $('.files').last()[0]
                @snapper = new Snap
                    element: element
                    disable: 'right'
                    maxPosition: element.offsetWidth
                    stopPropagation: false
                @snapper.on 'open', =>
                    if ++@back is 1
                        log.info @parentPath
                        @router.layout.goBack()
                        path = @router.layout.currentView.path
                        @router.navigate "folder#{path}", trigger: false
            , 1000


    update: ->
        @load @options.path
