# Faithful Customer TicketDetail — matches docs/ui-references/customer-portal/.
# Dispatched from TicketZoomRouter (in ticket_zoom.coffee) when the user is
# a customer. Renders a clean threaded conversation rather than the agent
# zoom layout.
class App.CustomerTicketDetail extends App.Controller
  @requiredPermission: 'ticket.customer'

  elements:
    '.js-reply-body':   'replyInput'
    '.js-thread':       'thread'

  events:
    'click .js-back':      'onBack'
    'click .js-send':      'onSend'
    'click .js-discard':   'onDiscard'
    'click .js-resolve':   'onResolve'
    'click .js-reopen':    'onReopen'
    'input .js-reply-body':'onReplyInput'
    'change .js-reply-file':'onFileSelect'
    'click .js-remove-file':'onFileRemove'

  constructor: (params) ->
    super
    @ticket_id = params.ticket_id
    @title __('Loading…'), true

    # Defensive: TaskManager re-fires persistent tasks on route changes
    # and may invoke this controller without a ticket_id when navigating
    # away. Don't issue a /tickets/undefined?... request in that case —
    # just render an empty placeholder.
    if !@ticket_id
      @renderLoading()
      return

    @draft = ''
    @form_id = App.ControllerForm.formId()
    @attachments = []
    @ticket_article_ids = []
    @loadTicket()

  release: =>
    super

  loadTicket: =>
    @ajax(
      id:    "customer_ticket_detail_#{@ticket_id}"
      type:  'GET'
      url:   "#{@apiPath}/tickets/#{@ticket_id}?all=true"
      processData: true
      success: (data) =>
        # /tickets/{id}?all=true returns the ticket id under .id and the
        # full asset payload under .assets — load assets so App.Ticket and
        # App.TicketArticle have records to look up.
        App.Collection.loadAssets(data.assets) if data?.assets
        @ticket_article_ids = data.article_ids or data.ticket_article_ids or []
        @ticket = App.Ticket.find(@ticket_id)
        if @ticket
          @title @ticket.title, true
          @navupdate "#ticket/zoom/#{@ticket.id}"
        @render()
      error: =>
        @notify(type: 'error', msg: __('Could not load ticket.'))
    )

  onBack: (e) =>
    e.preventDefault()
    @navigate '#ticket/view/my_tickets'

  onReplyInput: (e) =>
    @draft = e.target.value

  onFileSelect: (e) =>
    files = Array.from(e.target.files or [])
    return if !files.length
    for file in files
      @uploadFile(file)
    e.target.value = ''

  uploadFile: (file) =>
    formData = new FormData()
    formData.append('File', file)
    formData.append('form_id', @form_id)
    @ajax(
      id:          "upload_#{@form_id}_#{file.name}"
      type:        'POST'
      url:         "#{@apiPath}/upload_caches/#{@form_id}"
      data:        formData
      processData: false
      contentType: false
      success: (data) =>
        @attachments.push(
          id:       data.data?.id
          filename: file.name
          size:     file.size
        )
        @renderAttachments()
    )

  onFileRemove: (e) =>
    e.preventDefault()
    idx = parseInt($(e.currentTarget).data('idx'), 10)
    att = @attachments[idx]
    if att?.id
      @ajax(
        type: 'DELETE'
        url:  "#{@apiPath}/upload_caches/#{@form_id}/items/#{att.id}"
      )
    @attachments.splice(idx, 1)
    @renderAttachments()

  renderAttachments: =>
    container = @el.find('.js-reply-attachments')
    return if !container.length
    html = ''
    for att, i in @attachments
      size = if att.size < 1024 then "#{att.size} B"
      else if att.size < 1024 * 1024 then "#{Math.round(att.size / 1024)} KB"
      else "#{(att.size / 1024 / 1024).toFixed(1)} MB"
      html += "<span class=\"cp-reply-file\">📎 #{_.escape(att.filename)} (#{size}) <a class=\"js-remove-file\" data-idx=\"#{i}\" href=\"#\">×</a></span>"
    container.html(html)

  onDiscard: (e) =>
    e.preventDefault()
    @draft = ''
    @replyInput.val('') if @replyInput

  onSend: (e) =>
    e.preventDefault()
    return if !@draft or !@draft.trim()
    return if @sending
    @sending = true

    article = new App.TicketArticle
    article.load(
      ticket_id:   @ticket.id
      type_id:     App.TicketArticleType.findByAttribute('name', 'web')?.id
      sender_id:   App.TicketArticleSender.findByAttribute('name', 'Customer')?.id
      from:        App.Session.get().displayName()
      to:          @ticket.group?.name or ''
      subject:     ''
      body:        @draft
      content_type: 'text/plain'
      internal:    false
      form_id:     @form_id
    )
    article.save(
      done: =>
        @draft = ''
        @attachments = []
        @form_id = App.ControllerForm.formId()
        @sending = false
        @loadTicket()
        @notify(type: 'success', msg: __('Reply sent.'))
      fail: (settings, details) =>
        @sending = false
        @notify(type: 'error', msg: details?.error_human or __('Could not send reply.'))
    )

  onResolve: (e) =>
    e.preventDefault()
    @updateState('closed')

  onReopen: (e) =>
    e.preventDefault()
    @updateState('open')

  updateState: (stateName) =>
    state = App.TicketState.findByAttribute('name', stateName)
    return if !state
    ticket = App.Ticket.find(@ticket.id)
    ticket.state_id = state.id
    ticket.save(
      done: =>
        @loadTicket()
        @notify(type: 'success', msg: __('Ticket updated.'))
    )

  relTime: (iso) ->
    return '' if !iso
    d = new Date(iso)
    d.toLocaleString(undefined, month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit')

  bucketFor: (ticket) ->
    state = if ticket then App.TicketState.find(ticket.state_id) else null
    stateType = if state then App.TicketStateType.find(state.state_type_id) else null
    return 'closed' if state?.name in ['closed', 'merged']
    return 'pending'  if stateType?.name in ['pending reminder', 'pending action']
    return 'resolved' if stateType?.name is 'closed'
    'open'

  authorOf: (article) ->
    sender = if article.sender_id then App.TicketArticleSender.find(article.sender_id) else null
    isAgent = sender?.name is 'Agent' or sender?.name is 'System'
    me = App.Session.get()
    isSelf = me and article.created_by_id and article.created_by_id is me.id
    user = if article.created_by_id then App.User.find(article.created_by_id) else null
    name =
      if isSelf
        __('You')
      else if isAgent
        user?.fullname or __('Support')
      else
        user?.fullname or article.from?.replace(/\s*<[^>]+>/, '') or __('Customer')
    { isAgent: !!isAgent, name: name }

  initialsOf: (article) ->
    user = if article.created_by_id then App.User.find(article.created_by_id) else null
    return '?' if !user
    if user.firstname and user.lastname
      (user.firstname[0] + user.lastname[0]).toUpperCase()
    else if user.firstname
      user.firstname.slice(0, 2).toUpperCase()
    else if user.email
      user.email[0].toUpperCase()
    else
      '?'

  decoratedArticles: ->
    return [] if !@ticket_article_ids or @ticket_article_ids.length is 0
    rows = []
    for id in @ticket_article_ids
      a = App.TicketArticle.find(id)
      continue if !a
      who = @authorOf(a)
      attachments = []
      if a.attachments
        for att in a.attachments
          attachments.push
            id:       att.id
            filename: att.filename
            size:     att.size
            url:      "#{@apiPath}/ticket_attachment/#{@ticket_id}/#{a.id}/#{att.id}"
      rows.push
        id:            a.id
        body:          a.body
        internal:      a.internal
        created_at:    a.created_at
        isAgent:       who.isAgent
        displayAuthor: who.name
        initials:      @initialsOf(a)
        attachments:   attachments
    rows

  render: =>
    return @renderLoading() if !@ticket

    bucket = @bucketFor(@ticket)
    state  = App.TicketState.find(@ticket.state_id)
    priority = App.TicketPriority.find(@ticket.priority_id)
    group  = App.Group.find(@ticket.group_id)
    articles = @decoratedArticles()

    @html App.view('customer_ticket_detail')(
      ticket:        @ticket
      number:        @ticket.number
      title:         @ticket.title
      bucket:        bucket
      stateName:     state?.name
      priorityName:  priority?.name or 'normal'
      groupName:     group?.name or ''
      createdAt:     @relTime(@ticket.created_at)
      articles:      articles
      draft:         @draft
      isResolved:    bucket is 'resolved'
      isClosed:      bucket is 'closed'
      relTime:       (iso) => @relTime(iso)
      pillClass:     "cp-pill cp-pill--#{bucket}"
      priClass:      (->
        if /high|3/i.test(priority?.name or '') then 'cp-pri cp-pri--high'
        else if /low|1/i.test(priority?.name or '') then 'cp-pri cp-pri--low'
        else 'cp-pri cp-pri--normal'
      )()
    )

  renderLoading: =>
    @html '<div class="cp-empty" style="padding:60px 28px;">' + App.i18n.translateContent('Loading…') + '</div>'

App.Config.set('CustomerTicketDetail', { controller: 'CustomerTicketDetail', permission: ['ticket.customer'] }, 'permanentTask')
