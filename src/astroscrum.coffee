# Description:
#   Interface with Astroscrum API
#
# Configuration:
#   HUBOT_ASTROSCRUM_AUTH_TOKEN
#   HUBOT_URL (usually set by default on heroku)
#
# Options:
#   HUBOT_ASTROSCRUM_URL
#
# Commands:
#   hubot scrum join - join your team's daily scrum
#   hubot scrum players - return all the players on your team
#   hubot scrum help - get help on how to do your scrum
#   hubot scrum summary - returns the current summary for today
#   hubot today - what you're doing today, you can have many entries
#   hubot yesterday - what you did yesterday
#   hubot blocked - what you are blocked by
#

HOST_URL = process.env.HUBOT_URL || "https://astroscrum-slackbot.herokuapp.com"
url = process.env.HUBOT_ASTROSCRUM_URL || "https://astroscrum-api.herokuapp.com/v1"

# Default time to tell users to do their scrum
PROMPT_AT = process.env.HUBOT_SCRUM_PROMPT_AT || "0 6 * * * 1-5" # 6am everyday

# Default scrum reminder time
REMIND_AT = process.env.HUBOT_SCRUM_REMIND_AT || "30 11 * * * 1-5" # 11:30am everyday

# Send the scrum at 10 am everyday
SUMMARY_AT = process.env.HUBOT_SCRUM_SUMMARY_AT || "0 12 * * * 1-5" # noon

# Set to local timezone
TIMEZONE = process.env.TZ || "America/Los_Angeles"


# Handlebars
Handlebars = require('handlebars')

# HTTP Requests
Request = require('request')

# Setup Redis
if process.env.REDISCLOUD_URL
  redis_url = require('url').parse(process.env.REDISCLOUD_URL)
  console.log('>>>>>>> redis_url', process.env.REDISCLOUD_URL)
  redis = require('redis').createClient(redis_url.port, redis_url.hostname)
  console.log('>>>>>>> redis_url parsed', process.env.REDISCLOUD_URL)
  redis.auth redis_url.auth.split(':')[1]
else
  redis = require('redis').createClient()

get = (path, handler) ->
  redis.get 'hubot:storage', (err, reply) ->
    token = JSON.parse(reply)["_private"]["astroscrum-auth-token"]
    options = { url: url + path, headers: "X-Auth-Token": token }
    Request.get options, (err, res, body) ->
      handler JSON.parse(body)

post = (path, data, handler) ->
  redis.get 'hubot:storage', (err, reply) ->
    token = JSON.parse(reply)["_private"]["astroscrum-auth-token"]
    options = { url: url + path, json: data, headers: "X-Auth-Token": token }
    console.log('>>>>>>> post options', options)
    Request.post options, (err, res, body) ->
      console.log('>>>>>>> post response status code', res.statusCode)
      handler JSON.stringify(body)

put = (path, data, handler) ->
  redis.get 'hubot:storage', (err, reply) ->
    token = JSON.parse(reply)["_private"]["astroscrum-auth-token"]
    options = { url: url + path, json: data, headers: "X-Auth-Token": token }
    Request.put options, (err, res, body) ->
      handler JSON.stringify(body)

del = (path, data, handler) ->
  redis.get 'hubot:storage', (err, reply) ->
    token = JSON.parse(reply)["_private"]["astroscrum-auth-token"]
    options = { url: url + path, json: data, headers: "X-Auth-Token": token }
    Request.del options, (err, res, body) ->
      handler JSON.stringify(body)


setup = (robot, handler) ->
  data =
    team:
      slack_id: robot.adapter.client.team.id
      name: robot.adapter.client.team.name
      bot_url: HOST_URL
      timezone: TIMEZONE
      prompt_at: PROMPT_AT
      remind_at: REMIND_AT
      summary_at: SUMMARY_AT

  post '/team', data, (response) ->
    response = JSON.parse(response)
    handler response
    console.log "hubot-astroscrum connected to:", url
    console.log "team:", response

# Templates
templates =
  players: (players) ->
    source = """
      {{#players}}
      *{{real_name}}* ({{points}})
      {{/players}}
    """
    template = Handlebars.compile(source)
    template(players)

  summary: (resp) ->
    scrum = resp.scrum

    console.log(scrum)

    source = """
    Team summary for {{date}}:
    {{#players}}
    {{#filed}}
    *{{real_name}}* ({{points}})
    {{#categories}}
      {{category}}: {{#each entries}}{{body}}; {{/each}}
    {{/categories}}
    {{/filed}}

    Not filed:
    {{#not_filed}}
    *{{real_name}}* ({{points}})
    {{/not_filed}}
    {{/players}}
    """

    template = Handlebars.compile(source)
    template(scrum)

  join: (player) ->
    console.log(player)
    source = """
      {{player.name}}, you've joined Astroscrum
    """
    template = Handlebars.compile(source)
    template(player)

  entry: (entry) ->
    console.log(entry)
    source = """
      Got it! {{entry.category}}, {{entry.body}}
    """
    template = Handlebars.compile(source)
    template(entry)

  del: (entries) ->
    console.log(entries)
    source = """
      Okay, I deleted these entries:
      {{#entries}}
        • {{category}}: {{body}} (-{{points}})
      {{/entries}}
    """
    template = Handlebars.compile(source)
    template(entries)

  help: (player) ->
    console.log(player)
    source = """
      Hey {{player.name}}, you can say "today I need to organize my desk", "yesterday I cleaned up some code", or "blocked @mogramer owes me something".

      You can enter something for each of these:
       • *today*
       • *yesterday*
       • *blocked* (optional)

      You can find additional help:
       • in our Slack channel slack.astroscrum.com
       • in Github issues github.com/astroscrum/hubot-astroscrum/issues
       • by checking status.astroscrum.com to see if their is a system issue
       • by tweeting to us twitter.com/astroscrum
    """
    template = Handlebars.compile(source)
    template(player)

module.exports = (robot) ->

  ##
  # Gets auth token and saves it to Redis
  robot.brain.on 'loaded', (data) ->
    setup robot, (response) ->
      authToken = robot.brain.get "astroscrum-auth-token"

      if authToken
        console.log('Astroscrum team saved!', authToken)
      else
        robot.brain.set "astroscrum-auth-token", response.team.auth_token

  ##
  # Handle initial user creation
  robot.respond /scrum join/i, (msg) ->
    data =
      player: msg.envelope.user

    post '/slack/join', data, (response) ->
      response = JSON.parse(response)
      robot.send { room: msg.envelope.user.name }, templates.join(response)

  robot.respond /scrum players/i, (msg) ->
    get '/players', (response) ->
      robot.send { room: msg.envelope.user.name }, templates.players(response)

  robot.respond /scrum summary/i, (msg) ->
    get '/scrum', (response) ->
      robot.send { room: msg.envelope.user.name }, templates.summary(response)

  robot.respond /scrum notifications (on|off)/i, (msg) ->
    player = robot.brain.userForId(msg.envelope.user.id)
    # notifications = if msg.match[1] == "on" then true else false
    data =
      player:
        notifications: false # notifications

    put '/players/' + player.id, data, (response) ->
      response = JSON.parse(response)
      robot.send { room: msg.envelope.user.name }, "notifications are off" # templates.join(response)

  robot.respond /scrum clear/i, (msg) ->
    player = robot.brain.userForId(msg.envelope.user.id)
    data =
      entries:
        slack_id: player.id
        category: null

    del '/entries', data, (response) ->
      response = JSON.parse(response)
      robot.send { room: msg.envelope.user.name }, templates.del(response)

  robot.respond /(today|yesterday|blocked) (.*)/i, (msg) ->
    player = robot.brain.userForId(msg.envelope.user.id)
    data =
      entry:
        slack_id: player.id
        category: msg.match[1]
        body: msg.match[2]

    post '/entries', data, (response) ->
      console.log('>>>>>>> /entries response', response)
      response = JSON.parse(response)
      robot.send { room: msg.envelope.user.name }, templates.entry(response)

  robot.respond /scrum help/i, (msg) ->
    get '/players/' + msg.envelope.user.id, (response) ->
      robot.send { room: msg.envelope.user.name }, templates.help(response)

  # Direct message entire team
  robot.router.post "/hubot/astroscrum/announce", (req, res) ->
    console.log(req.body)
    template = Handlebars.compile(req.body.template)
    robot.send { room: req.body.channel }, template(req.body.data)
    res.send 'OK'

  # Direct message specific user
  robot.router.post "/hubot/astroscrum/message", (req, res) ->
    console.log(req.body)
    template = Handlebars.compile(req.body.template)
    for slack_id in req.body.players
      player = robot.brain.userForId(slack_id)
      robot.send { room: player.name }, template(req.body.data)
    res.send 'OK'
