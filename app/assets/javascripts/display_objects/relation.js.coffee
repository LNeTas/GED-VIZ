define [
  'jquery'
  'raphael'
  'chaplin/mediator'
  'display_objects/display_object'
  'lib/colors'
  'lib/i18n'
  'lib/number_formatter'
  'lib/utils'
], ($, Raphael, mediator, DisplayObject, Colors, I18n, numberFormatter, utils) ->
  'use strict'

  # Shortcuts
  # ---------

  PI = Math.PI
  HALF_PI = PI / 2

  sin = Math.sin
  cos = Math.cos

  EASE_IN = 'easeIn'
  EASE_OUT = 'easeOut'

  # Constants
  # ---------

  NORMAL_COLOR = Colors.black
  STROKE_OPACITY = 0.1
  ARROW_SIZE = 10
  PERCENT_LABEL_DISTANCE = 20
  ACTIVE_OPACITY = 0.9

  class Relation extends DisplayObject

    # Property declarations
    # ---------------------

    # id: String
    #   from and to ID connected with a “>”, like fr>us
    # from: Element
    # fromId: String
    # to: Element
    # toId: String
    # amount: Number
    # stackedAmountFrom: Number
    # stackedAmountTo: Number
    # missingRelations: Object
    # $container: jQuery
    #
    # path: Raphael.Element
    # destinationArrow: Raphael.Element
    # sourceArrow: Raphael.Element
    # labelContainer: jQuery
    # fadeDuration: Number
    # lookAnimation: Raphael.Animation
    #   Current animation of the path look, not the position
    #
    # Drawing variables which are passed in:
    #
    # animationDuration: Number
    # chartDrawn: Boolean

    DRAW_OPTIONS: 'animationDuration chartDrawn'.split(' ')

    constructor: (@fromId, @from, @toId, @to, @amount, @stackedAmountFrom,
      @stackedAmountTo, @missingRelations, @$container) ->
      super

      @id = "#{fromId}>#{toId}"

      @initStates
        states:

          # Locking
          locked: ['on', 'off']

          # Path states
          #   normal: light gray
          #   highlight: highlighted temporarily by hover, dark gray
          #   active: highlighted permanently by click, dark gray
          #   activeIn: red incoming relation, green arrow at source
          #   activeOut: green outgoing relation,
          #              green arrows at source and destination
          path: ['normal', 'highlight', 'active', 'activeIn', 'activeOut'],

          # labels states
          #   on: display labels
          #   off: hide labels
          labels: ['on', 'off']

        initialState:
          locked: 'off'
          path: 'normal'
          labels: 'off'

    # When being hidden, remove all children and return to undrawn state
    hide: ->
      if @drawn
        @animationDeferred?.reject()
        @removeChildren()
        # Remove additional references to DOM elements etc.
        props = 'path destinationArrow sourceArrow' +
          'labelContainer fadeDuration lookAnimation'
        for prop in props.split(' ')
          delete @[prop]
      super

    # Main drawing method
    # -------------------

    draw: (options, drawInverseFrom = false, drawInverseTo = false) ->

      @saveDrawOptions options
      {paper} = options

      @fadeDuration = @animationDuration / 2

      return unless @visible and @from and @to

      fromMagnet = @from.magnet
      toMagnet = @to.magnet

      # Fix for inner-country relations in charts with 1-2 elements
      if @from is @to
        drawInverseTo = drawInverseFrom

      # Helper for getting start and end point of relation line
      relationLinePointFromFace =
        x: (face, totalAmount, stackedAmount) =>
          face.start.x +
          ((face.end.x - face.start.x) / totalAmount * (stackedAmount - (@amount / 2))) +
          offset.x
        y: (face, totalAmount, stackedAmount) =>
          face.start.y +
          ((face.end.y - face.start.y) / totalAmount * (stackedAmount - (@amount / 2))) +
          offset.y

      offset =
        x: paper.width / 2
        y: paper.height / 2

      stackedAmounts =
        from: @from.sumOut - @stackedAmountFrom
        to: @to.sumIn - @stackedAmountTo

      # get faces of source and destination magnets
      sourceFace =
        start:
          x: unless drawInverseFrom then fromMagnet.x1 else fromMagnet.x2
          y: unless drawInverseFrom then fromMagnet.y1 else fromMagnet.y2
        end:
          x: unless drawInverseFrom then fromMagnet.x2 else fromMagnet.x1
          y: unless drawInverseFrom then fromMagnet.y2 else fromMagnet.y1
      destinationFace =
        start:
          x: unless drawInverseTo then toMagnet.x2 else toMagnet.x3
          y: unless drawInverseTo then toMagnet.y2 else toMagnet.y3
        end:
          x: unless drawInverseTo then toMagnet.x3 else toMagnet.x2
          y: unless drawInverseTo then toMagnet.y3 else toMagnet.y2

      sourceFace.length = Math.sqrt(
        Math.pow(sourceFace.end.x - sourceFace.start.x, 2) +
        Math.pow(sourceFace.end.y - sourceFace.start.y, 2)
      )

      # get relation line start and end point
      relationLine =
        start:
          x: relationLinePointFromFace.x(sourceFace, @from.sumOut, stackedAmounts.from)
          y: relationLinePointFromFace.y(sourceFace, @from.sumOut, stackedAmounts.from)
        end:
          x: relationLinePointFromFace.x(destinationFace, @to.sumIn, stackedAmounts.to)
          y: relationLinePointFromFace.y(destinationFace, @to.sumIn, stackedAmounts.to)

      # distance from startFace.start <-> destinationFace.start
      distance = Math.sqrt(
        Math.pow(relationLine.end.y - relationLine.start.y, 2) +
        Math.pow(relationLine.end.x - relationLine.start.x, 2)
      )

      controlPointDistance = distance * 0.4

      # some trigonometry for control points
      degrees = {}
      degrees.start = {}
      degrees.start.deg = if drawInverseFrom
        Math.atan2(sourceFace.start.y - sourceFace.end.y, sourceFace.start.x - sourceFace.end.x) - HALF_PI
      else
        Math.atan2(sourceFace.end.y - sourceFace.start.y, sourceFace.end.x - sourceFace.start.x) - HALF_PI
      degrees.start.cos = Math.cos degrees.start.deg
      degrees.start.sin = Math.sin degrees.start.deg
      degrees.start.distCos = degrees.start.cos * controlPointDistance
      degrees.start.distSin = degrees.start.sin * controlPointDistance

      degrees.end = {}
      degrees.end.deg = if drawInverseTo
        Math.atan2(destinationFace.start.y - destinationFace.end.y, destinationFace.start.x - destinationFace.end.x) - HALF_PI
      else
        Math.atan2(destinationFace.end.y - destinationFace.start.y, destinationFace.end.x - destinationFace.start.x) - HALF_PI
      degrees.end.cos = Math.cos degrees.end.deg
      degrees.end.sin = Math.sin degrees.end.deg
      degrees.end.distCos = degrees.end.cos * controlPointDistance
      degrees.end.distSin = degrees.end.sin * controlPointDistance

      # Calculate bézier control points for start and end
      controlPoint =
        start:
          x: relationLine.start.x - degrees.start.distCos
          y: relationLine.start.y - degrees.start.distSin
        end:
          x: relationLine.end.x - degrees.end.distCos
          y: relationLine.end.y - degrees.end.distSin

      @debugPoint controlPoint.start.x,controlPoint.start.y
      @debugPoint controlPoint.end.x,controlPoint.end.y

      relationLine.pathString =
        # Curve from start through both control points to end
        'M' + relationLine.start.x + ',' + relationLine.start.y +
        'C' + controlPoint.start.x + ',' + controlPoint.start.y +
        ' ' + controlPoint.end.x + ',' + controlPoint.end.y +
        ' ' + relationLine.end.x + ',' + relationLine.end.y

      strokeWidth = (sourceFace.length / @from.sumOut) * @amount
      strokeWidth = Math.max(strokeWidth, 0.8)

      # Finally draw the paths
      # ----------------------

      # Initialize Deferred which tracks whether all parts have been drawn
      @animationDeferred?.reject()
      @animationDeferred = $.Deferred()

      # Curry the drawArrows function to use it as an animation callback
      drawArrows = _.bind @drawArrows, @,
        paper, sourceFace, destinationFace, stackedAmounts, degrees, offset

      if @drawn
        # Hide the arrows during the animation
        @hideArrows()

        # Animate existing path, stop all running animations
        @path.stop().animate(
          { path: relationLine.pathString, 'stroke-width': strokeWidth },
          @animationDuration,
          EASE_OUT,
          # Move arrows after animation
          drawArrows
        )

        @drawn = true
        return

      # Path hasn’t been drawn before, create it from scratch
      @path = paper.path(relationLine.pathString).attr(
        stroke: NORMAL_COLOR
        'stroke-opacity': if @chartDrawn then 0 else STROKE_OPACITY
        'stroke-width': strokeWidth
        #'stroke-dasharray': '.' # N/A
      )
      @addChild @path

      # If the relation belongs to a country which was recently added
      # to the chart, fade in the path
      if @chartDrawn
        afterTransition = if @animationDuration > 0
          @animationDuration + 100
        else
          0
        animation = Raphael.animation(
          { 'stroke-opacity': STROKE_OPACITY },
          @fadeDuration,
          EASE_OUT,
          # Draw arrows after animation
          drawArrows
        ).delay(afterTransition)
        @path.animate animation
      else
        # Immediately draw the arrows
        drawArrows()
        @animationDeferred.resolve()

      @registerMouseHandlers()

      @drawn = true
      return

    # Drawing the arrows
    # ------------------

    drawArrows: (paper, sourceFace, destinationFace, stackedAmounts, degrees, offset) =>
      delta =
        source:
          x: sourceFace.end.x - sourceFace.start.x
          y: sourceFace.end.y - sourceFace.start.y
        destination:
          x: destinationFace.end.x - destinationFace.start.x
          y: destinationFace.end.y - destinationFace.start.y

      deltaAmountFraction =
        sourceXFrom: delta.source.x / @from.sumOut
        sourceYFrom: delta.source.y / @from.sumOut
        destinationXTo: delta.destination.x / @to.sumIn
        destinationYTo: delta.destination.y / @to.sumIn

      # Source points

      sourcePoints =
        one:
          x: sourceFace.start.x + (deltaAmountFraction.sourceXFrom * stackedAmounts.from) + offset.x
          y: sourceFace.start.y + (deltaAmountFraction.sourceYFrom * stackedAmounts.from) + offset.y
        two:
          x: sourceFace.start.x + (deltaAmountFraction.sourceXFrom * (stackedAmounts.from - @amount)) + offset.x
          y: sourceFace.start.y + (deltaAmountFraction.sourceYFrom * (stackedAmounts.from - @amount)) + offset.y

      sourcePoints.one.finalX = sourcePoints.one.x + degrees.start.cos
      sourcePoints.one.finalY = sourcePoints.one.y + degrees.start.sin
      sourcePoints.two.finalX = sourcePoints.two.x + degrees.start.cos
      sourcePoints.two.finalY = sourcePoints.two.y + degrees.start.sin

      sourcePoints.three =
        finalX: sourcePoints.one.x + (sourcePoints.two.x - sourcePoints.one.x) / 2 - degrees.start.cos * ARROW_SIZE
        finalY: sourcePoints.one.y + (sourcePoints.two.y - sourcePoints.one.y) / 2 - degrees.start.sin * ARROW_SIZE

      # Destination points

      destinationPoints =
        one:
          x: destinationFace.start.x + (deltaAmountFraction.destinationXTo * stackedAmounts.to) + offset.x
          y: destinationFace.start.y + (deltaAmountFraction.destinationYTo * stackedAmounts.to) + offset.y
        two:
          x: destinationFace.start.x + (deltaAmountFraction.destinationXTo * (stackedAmounts.to - @amount)) + offset.x
          y: destinationFace.start.y + (deltaAmountFraction.destinationYTo * (stackedAmounts.to - @amount)) + offset.y

      destinationPoints.one.finalX = destinationPoints.one.x - degrees.end.cos
      destinationPoints.one.finalY = destinationPoints.one.y - degrees.end.sin
      destinationPoints.two.x - degrees.end.cos
      destinationPoints.two.y - degrees.end.sin

      destinationPoints.three =
        finalX: destinationPoints.one.x + (destinationPoints.two.x - destinationPoints.one.x) / 2 + degrees.end.cos * ARROW_SIZE
        finalY: destinationPoints.one.y + (destinationPoints.two.y - destinationPoints.one.y) / 2 + degrees.end.sin * ARROW_SIZE

      # Path strings

      sourcePathString =
        'M' + sourcePoints.one.finalX + ',' + sourcePoints.one.finalY +
        'L' + sourcePoints.two.finalX + ',' + sourcePoints.two.finalY +
        'L' + sourcePoints.three.finalX + ',' + sourcePoints.three.finalY

      destinationArrowPathString =
        'M' + destinationPoints.one.finalX + ',' + destinationPoints.one.finalY +
        'L' + destinationPoints.two.finalX + ',' + destinationPoints.two.finalY +
        'L' + destinationPoints.three.finalX + ',' + destinationPoints.three.finalY

      if @sourceArrow and @destinationArrow
        # Just move the existing arrows
        @sourceArrow.attr path: sourcePathString
        @destinationArrow.attr path: destinationArrowPathString
        @animationDeferred.resolve()
        return

      # Draw arrows from scratch
      color = Colors.magnets[@from.dataType].outgoing
      @sourceArrow = paper.path(sourcePathString)
        .hide() # Start hidden
        .attr(fill: color, 'stroke-opacity': 0)
      @addChild @sourceArrow

      # Testing a glow
      #sourceStrokePath =
      #  'M' + sourcePoints.one.finalX + ',' + sourcePoints.one.finalY +
      #  'L' + sourcePoints.three.finalX + ',' + sourcePoints.three.finalY  +
      #  'L' + sourcePoints.two.finalX + ',' + sourcePoints.two.finalY
      #paper.path(sourceStrokePath).attr(stroke: 'white', 'stroke-width': 2, 'stroke-linecap': 'butt')

      @destinationArrow = paper.path(destinationArrowPathString)
        .hide() # Start hidden
        .attr(fill: Colors.gray, 'stroke-opacity': 0)
      @addChild @destinationArrow

      @animationDeferred.resolve()

      return

    hideArrows: ->
      @sourceArrow?.hide()
      @destinationArrow?.hide()
      return

    # Content box methods
    # -------------------

    showContextBox: ->
      mediator.publish 'contextbox:explainRelation',
        fromName: @from.name
        toName: @to.name
        dataType: @from.dataType
        amount: @amount
        unit: @from.unit
        percentFrom: (100 / @from.sumOut * @amount).toFixed(1) + '%'
        percentTo: (100 / @to.sumIn * @amount).toFixed(1) + '%'
        missingRelations: @missingRelations
        year: @from.year

    hideContextBox: ->
      mediator.publish 'contextbox:hide'

    # Mouse event handling
    # --------------------

    registerMouseHandlers: ->
      $(@path.node)
        .mouseenter(@mouseenterHandler)
        .mouseleave(@mouseleaveHandler)
        .click(@clicked)

    mouseenterHandler: =>
      # Fade in content box
      @showContextBox()

      # Highlight if normal
      if @state('path') is 'normal'
        @transitionTo 'path', 'highlight'

      # Show labels in any case
      @transitionTo 'labels', 'on'
      return

    mouseleaveHandler: (event) =>
      relatedTarget = event.relatedTarget

      # Stop if the target is the relation path
      if _(@displayObjects).some((obj) -> relatedTarget is obj.node) or
        @labelContainer and $.contains(@labelContainer.get(0), relatedTarget)
          return

      # Fade out content box
      @hideContextBox()

      pathState = @state 'path'

      # Reset if highlighted
      if pathState is 'highlight'
        @transitionTo 'path', 'normal'

      # Hide labels if not active
      unless pathState is 'active'
        @transitionTo 'labels', 'off'
      return

    clicked: =>
      # Toggle locking
      if @state('locked') is 'on'
        @transitionTo 'path', 'highlight'
        @transitionTo 'locked', 'off'
      else
        @transitionTo 'path', 'active'
        @transitionTo 'locked', 'on'
      return

    # Transitions
    # -----------

    # Path transition handlers
    # ------------------------

    enterPathNormalState: (oldState) ->
      return unless oldState and @drawn
      @setNormalLook()

    enterPathHighlightState: ->
      @setHighlightLook() if @drawn

    enterPathActiveState: ->
      @setHighlightLook() if @drawn

    enterPathActiveInState: ->
      @setActiveInLook() if @drawn

    enterPathActiveOutState: ->
      @setActiveOutLook() if @drawn

    # Labels transition handlers
    # --------------------------

    enterLabelsOnState: ->
      @createLabels() if @drawn

    enterLabelsOffState: ->
      @removeLabels() if @drawn

    # Transitions helpers
    # -------------------

    # Normal look: Gray translucent path, no arrows
    setNormalLook: ->
      @animatePathLook(
        { stroke: NORMAL_COLOR, 'stroke-opacity': STROKE_OPACITY },
        @fadeDuration,
        EASE_IN
      )
      @hideArrows()
      return

    # Highlighted: Gray opaque path, both arrows visible,
    # gray destination arrow
    setHighlightLook: ->
      # Wait for animation to complete
      @animationDeferred.done =>
        color = Colors.gray
        @path.toFront()
        @animatePathLook(
          { stroke: color, 'stroke-opacity': 1 },
          @fadeDuration,
          EASE_OUT
        )
        @sourceArrow.stop().attr('fill-opacity': 1).toFront().show()
        @destinationArrow.stop().toFront().show().animate(
          { fill: color, 'fill-opacity': 1 },
          @fadeDuration,
          EASE_OUT
        )
        return
      return

    # Active in: Red translucent path, only show source arrow
    setActiveInLook: ->
      @animationDeferred.done =>
        color = Colors.magnets[@from.dataType].incoming
        @animatePathLook(
          { stroke: color, 'stroke-opacity': ACTIVE_OPACITY },
          @fadeDuration,
          EASE_OUT
        )
        @sourceArrow.stop().toFront().show().animate(
          { 'fill-opacity': 0.25 },
          @fadeDuration,
          EASE_OUT
        )
        @destinationArrow.stop().hide()
        return
      return

    # Active out: Green translucent path, both arrows visible,
    # green destination arrow
    setActiveOutLook: ->
      @animationDeferred.done =>
        color = Colors.magnets[@from.dataType].outgoing
        @animatePathLook(
          { stroke: color, 'stroke-opacity': ACTIVE_OPACITY },
          @fadeDuration,
          EASE_OUT
        )
        @sourceArrow.stop().toFront().show().animate(
          { 'fill-opacity': 1 },
          @fadeDuration,
          EASE_OUT
        )
        @destinationArrow.stop().toFront().show().animate(
          { fill: color, 'fill-opacity': ACTIVE_OPACITY },
          @fadeDuration,
          EASE_OUT
        )
        return
      return

    # Helper for the path look animation (not the path itself).
    # Ensures that only one look animation is running.
    animatePathLook: (attributes, duration) ->
      return unless @path
      @path.stop @lookAnimation if @lookAnimation
      @lookAnimation = Raphael.animation attributes, duration, EASE_OUT
      @path.animate @lookAnimation
      return

    # Create labels
    # -------------

    createLabels: ->
      # Don’t create the labels twice
      return if @labelContainer

      # Create the container
      @labelContainer = $('<div>')
        .addClass('relation-labels')
        # Check target when the mouse leaves the labels
        .mouseleave(@mouseleaveHandler)
        # Allow activation by clicking on a label
        .click(@clicked)
        # Append to DOM
        .appendTo(@$container)
      @addChild @labelContainer

      # Get a point at the middle of the path to position the labels
      pathLength = @path.getTotalLength()
      middleOfPath = @path.getPointAtLength(pathLength / 2)
      x = middleOfPath.x
      y = middleOfPath.y

      # Create the value label
      # ----------------------

      number = numberFormatter.formatValue(
        @amount, @from.dataType, @from.unit, true
      )
      text = I18n.template(
        ['units', @from.unit, 'with_value_html']
        number: number
      )

      value = $('<div>')
        .addClass('relation-value-label')
        .append(text)
        # Append immediately to get the size
        .appendTo(@labelContainer)

      # Calculate bounding box
      valueBox =
        width: value.outerWidth()
        height: value.outerHeight()
      valueBox.x = x - valueBox.width / 2
      valueBox.y = y - valueBox.height - 1.5
      valueBox.x2 = valueBox.x + valueBox.width
      valueBox.y2 = valueBox.y + valueBox.height

      value.css(left: valueBox.x, top: valueBox.y)

      # Create the description label
      # ----------------------------

      text = I18n.template(
        ['relation', @from.dataType],
        from: @from.name, to: @to.name
      )

      description = $('<div>')
        .addClass('relation-description-label')
        .text(text)
        # Append immediately to get the size
        .appendTo(@labelContainer)

      # Calculate bounding box
      descriptionBox =
        width: description.outerWidth()
        height: description.outerHeight()
      descriptionBox.x = x - descriptionBox.width / 2
      descriptionBox.y = y + 1.5
      descriptionBox.x2 = descriptionBox.x + descriptionBox.width
      descriptionBox.y2 = descriptionBox.y + descriptionBox.height

      description.css(left: descriptionBox.x, top: descriptionBox.y)

      # Create the source percent label
      # -------------------------------

      text = (100 / @from.sumOut * @amount).toFixed(1) + ' %'

      source = $('<div>')
        .addClass('relation-percentage-label')
        .text(text)
        # Append immediately to get the size
        .appendTo(@labelContainer)

      # Calculate bounding box
      point = @path.getPointAtLength PERCENT_LABEL_DISTANCE
      srcBox =
        width: source.outerWidth()
        height: source.outerHeight()
      srcBox.x = point.x - srcBox.width / 2
      srcBox.y = point.y - srcBox.height / 2
      srcBox.x2 = srcBox.x + srcBox.width
      srcBox.y2 = srcBox.y + srcBox.height

      # Create the destination percent label
      # ------------------------------------

      text = (100 / @to.sumIn * @amount).toFixed(1) + ' %'

      destination = $('<div>')
        .addClass('relation-percentage-label')
        .text(text)
        # Append immediately to get the size
        .appendTo(@labelContainer)

      # Calculate bounding box
      point = @path.getPointAtLength pathLength - PERCENT_LABEL_DISTANCE
      destBox =
        width: destination.outerWidth()
        height: destination.outerHeight()
      destBox.x = point.x - destBox.width / 2
      destBox.y = point.y - destBox.height / 2
      destBox.x2 = destBox.x + destBox.width
      destBox.y2 = destBox.y + destBox.height

      # Position the percent labels
      # ---------------------------

      # If one box intersects with value/description,
      # move both over their magnets

      percentLabelsIntersect =
        Raphael.isBBoxIntersect(srcBox, valueBox) or
        Raphael.isBBoxIntersect(srcBox, descriptionBox) or
        Raphael.isBBoxIntersect(destBox, valueBox) or
        Raphael.isBBoxIntersect(destBox, descriptionBox)

      if percentLabelsIntersect

        dist = PERCENT_LABEL_DISTANCE

        # Move source label
        point = @path.getPointAtLength 0
        deg = @from.magnet.deg
        srcBox.x = point.x + cos(deg) * dist - srcBox.width / 2
        srcBox.y = point.y + sin(deg) * dist - srcBox.height / 2

        # Move destination label
        point = @path.getPointAtLength pathLength
        deg = @to.magnet.deg
        destBox.x = point.x + cos(deg) * dist - destBox.width / 2
        destBox.y = point.y + sin(deg) * dist - destBox.height / 2

      # Finally set their position
      source.css(left: srcBox.x, top: srcBox.y)
      destination.css(left: destBox.x, top: destBox.y)

      return

    # Remove labels
    # -------------

    removeLabels: ->
      return unless @labelContainer
      @labelContainer.remove()
      @removeChild @labelContainer
      delete @labelContainer

    # Fade out before disposal
    fadeOut: ->
      for child in @displayObjects when child.stop and child.animate
        child.stop().animate { opacity: 0 }, @animationDuration / 2
      return

    # Disposal
    # --------

    dispose: ->
      if @disposed
        console.log "Relation#dispose #{@id} already disposed"
        return

      # Remove references from elements
      @from.removeRelationOut this if @from
      @to.removeRelationIn    this if @to

      # Stop the animation Deferred
      @animationDeferred?.reject()

      super
