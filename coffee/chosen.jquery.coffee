###
Copyright (c) 2011 by Harvest
###
root = this
$ = jQuery

$.fn.extend({
  chosen: (data, options) ->
    # Do no harm and return as soon as possible for unsupported browsers, namely IE6 and IE7
    return this if $.browser.msie and ($.browser.version is "6.0" or  $.browser.version is "7.0")
    $(this).each((input_field) ->
      new Chosen(this, data, options) unless $(this).hasClass "chzn-done"
    )
})


class ChosenBase

  constructor: (element) ->
    @set_default_values()
    
    @form_field = element
    @$form_field = $ @form_field
    @is_rtl = @$form_field.hasClass "chzn-rtl"

    @set_up_html()
    @register_observers()
    @$form_field.addClass "chzn-done"

  default_text: ->
    return @$form_field.data 'placeholder' if @$form_field.data 'placeholder'

    if @form_field.multiple
      "Select Some Options"
    else
      "Select an Option"


  set_default_values: ->
    @active_field = false
    @mouse_on_container = false
    @results_showing = false
    @result_highlighted = null
    @result_single_selected = null
    @choices = 0

  container_id: ->
    container_id = if @form_field.id.length
      @form_field.id.replace(/(:|\.)/g, '_')
    else
      @generate_field_id()

    container_id += "_chzn"

  additional_container_classes: ->
    if @is_rtl
      'chzn-rtl'
    else
      ''

  build_container_div: ->
    container_div = ($ "<div />", {
      id: @container_id()
      class: "chzn-container #{@additional_container_classes()}"
      style: "width: #{@f_width}px"
    })

    container_div.html @container_div_content()

  set_up_html: ->
    @f_width = @$form_field.width()

    @$form_field.hide().after @build_container_div()
    @container = ($ '#' + @container_id())
    @dropdown = @container.find('div.chzn-drop').first()
    @set_container_class()
    
    @search_field = @container.find('input').first()
    @search_results = @container.find('ul.chzn-results').first()
    @search_field_scale()

    @search_no_results = @container.find('li.no-results').first()
    
    @initialize_search_container()
    
    @results_build()
    @set_tab_index()


  register_observers: ->
    @container.mousedown @container_mousedown
    @container.mouseenter @mouse_enter
    @container.mouseleave @mouse_leave
  
    @search_results.mouseup @search_results_mouseup
    @search_results.mouseover @search_results_mouseover
    @search_results.mouseout @search_results_mouseout

    @$form_field.bind "liszt:updated", @results_update_field

    @search_field.blur @input_blur
    @search_field.keyup @keyup_checker
    @search_field.keydown @keydown_checker


  container_mousedown: (evt) =>
    if evt and evt.type is "mousedown"
      evt.stopPropagation()
    if not @pending_destroy_click
      if not @active_field
        @search_field.val "" if @is_multiple
        $(document).click @test_active_click
        @results_show()
      else if not @is_multiple and evt and ($(evt.target) is @selected_item || $(evt.target).parents("a.chzn-single").length)
        evt.preventDefault()
        @results_toggle()

      @activate_field()
    else
      @pending_destroy_click = false


  select_item: (index) ->
    item = @results_data[index + '']
    id = @option_id_for_index(item.array_index)
    @selected_item.find("span").first().text item.text
    @container.find('li.result-selected').removeClass('result-selected')
    $("##{id}").addClass('result-selected')

  mouse_enter: => @mouse_on_container = true
  mouse_leave: => @mouse_on_container = false

  input_focus: (evt) =>
    setTimeout @container_mousedown, 50 unless @active_field
  
  input_blur: (evt) =>
    if not @mouse_on_container
      @active_field = false
      setTimeout @blur_test, 100

  blur_test: (evt) =>
    @close_field() if not @active_field and @container.hasClass "chzn-container-active"

  close_field: =>
    $(document).unbind "click", @test_active_click
    
    if not @is_multiple
      @selected_item.attr "tabindex", @search_field.attr("tabindex")
      @search_field.attr "tabindex", -1
    
    @active_field = false
    @results_hide()

    @container.removeClass "chzn-container-active"
    @winnow_results_clear()
    @clear_backstroke()

    @show_search_field_default()
    @search_field_scale()

  activate_field: =>
    if not @is_multiple and not @active_field
      @search_field.attr "tabindex", (@selected_item.attr "tabindex")
      @selected_item.attr "tabindex", -1

    @container.addClass "chzn-container-active"
    @active_field = true

    @search_field.val(@search_field.val())
    @search_field.focus()


  test_active_click: (evt) =>
    if $(evt.target).parents('#' + @container_id()).length
      @active_field = true
    else
      @close_field()
    
  results_build: ->
    @parsing = true
    @results_data = root.SelectParser.select_to_array @form_field

    if @is_multiple and @choices > 0
      @search_choices.find("li.search-choice").remove()
      @choices = 0
    else if not @is_multiple
      @selected_item.find("span").text @default_text()

    content = ''
    for data in @results_data
      if data.group
        content += @result_add_group data
      else if !data.empty
        content += @result_add_option data
        if data.selected and @is_multiple
          @choice_build data
        else if data.selected and not @is_multiple
          @selected_item.find("span").text data.text

    @show_search_field_default()
    @search_field_scale()
    
    @search_results.html content
    @parsing = false


  result_add_group: (group) ->
    if not group.disabled
      group.dom_id = @container_id() + "_g_" + group.array_index
      """<li id="#{group.dom_id}" class="group-result">#{$("<div />").text(group.label).html()}</li>"""
    else
      ""

  option_id_for_index: (index) ->
    @container_id() + "_o_" + index
  
  result_add_option: (option) ->
    if not option.disabled
      option.dom_id = @option_id_for_index(option.array_index)
      
      classes = if option.selected and @is_multiple then [] else ["active-result"]
      classes.push "result-selected" if option.selected
      classes.push "group-option" if option.group_array_index?
      
      """<li id="#{option.dom_id}" class="#{classes.join(' ')}">#{option.html}</li>"""
    else
      ""

  results_update_field: ->
    @result_clear_highlight()
    @result_single_selected = null
    @results_build()

  result_do_highlight: (el) ->
    if el.length
      @result_clear_highlight()

      @result_highlight = el
      @result_highlight.addClass "highlighted"

      maxHeight = parseInt @search_results.css("maxHeight"), 10
      visible_top = @search_results.scrollTop()
      visible_bottom = maxHeight + visible_top
      
      high_top = @result_highlight.position().top + @search_results.scrollTop()
      high_bottom = high_top + @result_highlight.outerHeight()

      if high_bottom >= visible_bottom
        @search_results.scrollTop if (high_bottom - maxHeight) > 0 then (high_bottom - maxHeight) else 0
      else if high_top < visible_top
        @search_results.scrollTop high_top
    
  result_clear_highlight: ->
    @result_highlight.removeClass "highlighted" if @result_highlight
    @result_highlight = null

  results_toggle: ->
    if @results_showing
      @results_hide()
    else
      @results_show()

  results_show: ->
    dd_top = if @is_multiple then @container.height() else (@container.height() - 1)
    @dropdown.css {"top":  dd_top + "px", "left":0}
    @results_showing = true

    @search_field.focus()
    @search_field.val @search_field.val()

    @winnow_results()

  update_search_field_width: ->
    @search_field.css width: @search_field_width() + "px"

  update_dropdown_width: ->
    @dropdown.css
      width: @dropdown_width() + "px"
      top: @dropdown_top() + "px"


  results_hide: ->
    @selected_item.removeClass "chzn-single-with-drop" unless @is_multiple
    @result_clear_highlight()
    @dropdown.css left: "-9000px"
    @results_showing = false


  set_tab_index: ->
    return unless @$form_field.attr "tabindex"

    ti = @$form_field.attr "tabindex"
    @$form_field.attr "tabindex", -1
    @update_selected_tab_index(ti)


  search_results_mouseup: (evt) =>
    target = if $(evt.target).hasClass "active-result" then $(evt.target) else $(evt.target).parents(".active-result").first()
    if target.length
      @result_highlight = target
      @result_select(evt)

  search_results_mouseover: (evt) =>
    target = if $(evt.target).hasClass "active-result" then $(evt.target) else $(evt.target).parents(".active-result").first()
    @result_do_highlight( target ) if target

  search_results_mouseout: (evt) =>
    @result_clear_highlight() if $(evt.target).hasClass "active-result" or $(evt.target).parents('.active-result').first()


  choices_click: (evt) =>
    evt.preventDefault()
    if( @active_field and not($(evt.target).hasClass "search-choice" or $(evt.target).parents('.search-choice').first) and not @results_showing )
      @results_show()

  choice_build: (item) ->
    choice_id = @container_id() + "_c_" + item.array_index
    @choices += 1
    @search_container.before """
      <li class="search-choice" id="#{choice_id}">
        <span>#{item.html}</span>
        <a href="javascript:void(0)" class="search-choice-close" rel="#{item.array_index}"></a>
      </li>
    """
    link = $('#' + choice_id).find("a").first()
    link.click (evt) => @choice_destroy_link_click(evt)

  choice_destroy_link_click: (evt) ->
    evt.preventDefault()
    @pending_destroy_click = true
    @choice_destroy $(evt.target)

  choice_destroy: (link) ->
    @choices -= 1
    @show_search_field_default()

    @results_hide() if @is_multiple and @choices > 0 and @search_field.val().length < 1

    @result_deselect (link.attr "rel")
    link.parents('li').first().remove()

  result_select: (evt) ->
    if @result_highlight
      high = @result_highlight
      high_id = high.attr "id"
      
      @result_clear_highlight()

      high.addClass "result-selected"
      
      if @is_multiple
        @result_deactivate high
      else
        @result_single_selected = high
      
      position = high_id.substr(high_id.lastIndexOf("_") + 1 )
      item = @results_data[position]
      item.selected = true

      @form_field.options[item.options_index].selected = true

      if @is_multiple
        @choice_build item
      else
        @selected_item.find("span").first().text item.text

      @results_hide() unless evt.metaKey and @is_multiple

      @search_field.val ""

      @$form_field.trigger "change"
      @search_field_scale()

  result_activate: (el) ->
    el.addClass("active-result").show()

  result_deactivate: (el) ->
    el.removeClass("active-result").hide()

  result_deselect: (pos) ->
    result_data = @results_data[pos]
    result_data.selected = false

    @form_field.options[result_data.options_index].selected = false
    result = $("#" + @container_id() + "_o_" + pos)
    result.removeClass("result-selected").addClass("active-result").show()

    @result_clear_highlight()
    @winnow_results()

    @$form_field.trigger "change"
    @search_field_scale()

  results_search: (evt) ->
    if @results_showing
      @winnow_results()
    else
      @results_show()

  winnow_results: ->
    @no_results_clear()
    
    results = 0

    searchText = if @search_field.val() is @default_text() then "" else $('<div/>').text($.trim(@search_field.val())).html()
    regex = new RegExp(searchText.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&"), 'i')

    for option in @results_data
      if not option.disabled and not option.empty
        if option.group
          $('#' + option.dom_id).hide()
        else if not (@is_multiple and option.selected)
          found = false
          result_id = option.dom_id
          
          if regex.test option.html
            found = true
            results += 1
          else if option.html.indexOf(" ") >= 0 or option.html.indexOf("[") == 0
            #TODO: replace this substitution of /\[\]/ with a list of characters to skip.
            parts = option.html.replace(/\[|\]/g, "").split(" ")
            if parts.length
              for part in parts
                if regex.test part
                  found = true
                  results += 1

          if found
            if searchText.length
              startpos = option.html.search regex
              text = option.html.substr(0, startpos + searchText.length) + '</em>' + option.html.substr(startpos + searchText.length)
              text = text.substr(0, startpos) + '<em>' + text.substr(startpos)
            else
              text = option.html

            $("#" + result_id).html text if $("#" + result_id).html != text

            @result_activate $("#" + result_id)

            $("#" + @results_data[option.group_array_index].dom_id).show() if option.group_array_index?
          else
            @result_clear_highlight() if @result_highlight and result_id is @result_highlight.attr 'id'
            @result_deactivate $("#" + result_id)
    
    if results < 1 and searchText.length
      @no_results searchText
    else
      @winnow_results_set_highlight()

  winnow_results_clear: ->
    @search_field.val ""
    lis = @search_results.find("li")

    for li in lis
      li = $(li)
      if li.hasClass "group-result"
        li.show()
      else if not @is_multiple or not li.hasClass "result-selected"
        @result_activate li

  winnow_results_set_highlight: ->
    if not @result_highlight

      selected_results = if not @is_multiple then @search_results.find(".result-selected") else []
      do_high = if selected_results.length then selected_results.first() else @search_results.find(".active-result").first()

      @result_do_highlight do_high if do_high?
  
  no_results: (terms) ->
    no_results_html = $('<li class="no-results">No results match "<span></span>"</li>')
    no_results_html.find("span").first().html(terms)

    @search_results.append no_results_html
  
  no_results_clear: ->
    @search_results.find(".no-results").remove()

  keydown_arrow: ->
    if not @result_highlight
      first_active = @search_results.find("li.active-result").first()
      @result_do_highlight $(first_active) if first_active
    else if @results_showing
      next_sib = @result_highlight.nextAll("li.active-result").first()
      @result_do_highlight next_sib if next_sib
    @results_show() if not @results_showing

  keyup_arrow: ->
    if not @results_showing and not @is_multiple
      @results_show()
    else if @result_highlight
      prev_sibs = @result_highlight.prevAll("li.active-result")
      
      if prev_sibs.length
        @result_do_highlight prev_sibs.first()
      else
        @results_hide() if @choices > 0
        @result_clear_highlight()

  keydown_backstroke: ->
    if @pending_backstroke
      @choice_destroy @pending_backstroke.find("a").first()
      @clear_backstroke()
    else
      @pending_backstroke = @search_container.siblings("li.search-choice").last()
      @pending_backstroke.addClass "search-choice-focus"

  clear_backstroke: ->
    @pending_backstroke.removeClass "search-choice-focus" if @pending_backstroke
    @pending_backstroke = null

  keyup_checker: (evt) =>
    stroke = evt.which ? evt.keyCode
    @search_field_scale()

    switch stroke
      when 8
        if @is_multiple and @backstroke_length < 1 and @choices > 0
          @keydown_backstroke()
        else if not @pending_backstroke
          @result_clear_highlight()
          @results_search()
      when 13
        evt.preventDefault()
        @result_select(evt) if @results_showing
      when 27
        @results_hide() if @results_showing
      when 9, 38, 40, 16, 91, 17
        # don't do anything on these keys
      else @results_search()


  keydown_checker: (evt) =>
    stroke = evt.which ? evt.keyCode
    @search_field_scale()
    
    @clear_backstroke() if stroke != 8 and @pending_backstroke
    
    switch stroke
      when 8
        @backstroke_length = @search_field.val().length
        break
      when 9
        @mouse_on_container = false
        break
      when 13
        evt.preventDefault()
        break
      when 38
        evt.preventDefault()
        @keyup_arrow()
        break
      when 40
        @keydown_arrow()
        break


  search_field_scale: ->
  
  generate_field_id: ->
    new_id = @generate_random_id()
    @form_field.id = new_id
    new_id
  
  generate_random_id: ->
    string = "sel" + @generate_random_char() + @generate_random_char() + @generate_random_char()
    while $("#" + string).length > 0
      string += @generate_random_char()
    string
    
  generate_random_char: ->
    chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXTZ"
    rand = Math.floor(Math.random() * chars.length)
    newchar = chars.substring rand, rand+1

class ChosenSingle extends ChosenBase
  is_multiple: false
  container_div_content: ->
    """
      <a href="javascript:void(0)" class="chzn-single">
        <span>#{@default_text()}</span>
        <div><b></b></div>
      </a>
      <div class="chzn-drop" style="left:-9000px;">
        <div class="chzn-search">
          <input type="text" autocomplete="off" />
        </div>
        <ul class="chzn-results"></ul>
      </div>
    """

  initialize_search_container: ->
    @search_container = @container.find('div.chzn-search').first()
    @selected_item = @container.find('.chzn-single').first()

  dropdown_top: ->
    @container.height()

  dropdown_width: ->
    @f_width - get_side_border_padding(@dropdown)

  search_field_width: ->
    @dropdown_width() - get_side_border_padding(@search_container) - get_side_border_padding(@search_field)

  register_observers: ->
    super
    @selected_item.focus @activate_field
    @$form_field.change @select_changed

  select_changed: (evt) =>
    @select_item(@form_field.selectedIndex)

  set_container_class: ->
    @container.addClass "chzn-container-single"

  update_selected_tab_index: (ti) ->
    @selected_item.attr "tabindex", ti
    @search_field.attr "tabindex", -1

  results_show: ->
    @selected_item.addClass "chzn-single-with-drop"
    if @result_single_selected
      @result_do_highlight( @result_single_selected )

    super
    @update_search_field_width()

  show_search_field_default: ->
    @search_field.val("")
    @search_field.removeClass "default"


class ChosenMultiple extends ChosenBase
  is_multiple: true
  container_div_content: ->
    """
      <ul class="chzn-choices">
        <li class="search-field">
          <input type="text" value="#{@default_text()}" class="default" autocomplete="off" style="width:25px;" />
        </li>
      </ul>
      <div class="chzn-drop" style="left:-9000px;">
        <ul class="chzn-results"></ul>
      </div>
    """

  initialize_search_container: ->
    @search_choices = @container.find('ul.chzn-choices').first()
    @search_container = @container.find('li.search-field').first()

  register_observers: ->
    super
    @search_choices.click @choices_click
    @search_field.focus @input_focus

  set_container_class: ->
    @container.addClass "chzn-container-multi"

  update_selected_tab_index: (ti) ->
    @search_field.attr "tabindex", ti

  show_search_field_default: ->
    if @choices < 1 and not @active_field
      @search_field.val @default_text()
      @search_field.addClass "default"
    else
      @search_field.val("")
      @search_field.removeClass "default"

  search_field_scale: ->
    h = 0
    w = 0

    style_block = "position:absolute; left: -1000px; top: -1000px; display:none;"
    styles = ['font-size','font-style', 'font-weight', 'font-family','line-height', 'text-transform', 'letter-spacing']
    
    for style in styles
      style_block += style + ":" + @search_field.css(style) + ";"
    
    div = $('<div />', { 'style' : style_block })
    div.text @search_field.val()
    $('body').append div

    w = div.width() + 25
    div.remove()

    if( w > @f_width - 10 )
      w = @f_width - 10

    @search_field.css width: w + 'px'

    dd_top = @container.height()
    @dropdown.css top:  dd_top + "px"


class Chosen
  constructor: (element) ->
    if element.multiple
      return new ChosenMultiple(element)
    else
      return new ChosenSingle(element)

get_side_border_padding = (elmt) ->
  elmt.outerWidth() - elmt.width()

root.get_side_border_padding = get_side_border_padding
