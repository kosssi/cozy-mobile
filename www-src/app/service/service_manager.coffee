
repeatingPeriod = 15 * 60 * 1000

module.exports = class ServiceManager extends Backbone.Model

    defaults: ->
        daemonActivated: false

    initialize: ->
        config = app.replicator.config
        # Initialize plugin with current config values.
        @listenNewPictures config, config.get 'syncImages'
        @toggle config, true

        # Listen to updates.
        @listenTo app.replicator.config, "change:syncImages", @listenNewPictures

        @checkActivated()

    isActivated: ->
        return @get 'daemonActivated'

    checkActivated: ->
        window.JSBackgroundService.isRepeating (err, isRepeating) =>
            if err
                console.log err
                isRepeating = false

            @set 'daemonActivated', isRepeating


    activate: (repeatingPeriod) ->
        window.JSBackgroundService.setRepeating repeatingPeriod, (err) =>
            if err then return console.log err
            @checkActivated()

    deactivate: ->
        window.JSBackgroundService.cancelRepeating (err) =>
            if err then return console.log err
            @checkActivated()

    toggle: (config, activate) ->
        if activate
            @deactivate()
        else
            @activate()

    listenNewPictures: (config, listen) ->
        window.JSBackgroundService.listenNewPictures listen, (err) ->
            if err then return console.log err
