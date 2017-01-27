# Description:
#   Decides which steam platform games an arbitrary group can (and should) play
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   hubot gametime - begin a new game selection in the current room
#   
#
# Notes:
#   None
#
# Author:
#   Ben Willard <willardb@gmail.com> (https://github.com/willardb)

C_SEAM_API_KEY = 'APIKEYGOESHERE-DONTCOMMIT'

steam_api_fetch = (robot, fetch, params) ->
	endpointMap = {
		games_owned: 'http://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/'
		game_info:	'http://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/'
	}

	query = { key: C_SEAM_API_KEY, format: 'json' }
	for tKey,tVal of params
		query[tKey] = tVal
	robot.logger.debug "about to promise"
	return new Promise (resolve, reject) ->
		robot.logger.debug "in promise"
		robot.http(endpointMap[fetch]).query(query).get() (err, res, body) ->
			robot.logger.debug "in http callback"
			if err or res.statusCode isnt 200
				robot.logger.debug "Steam API fetch error: #{err}"
				res.send "Steam API fetch error: #{err}"
				reject err
			try
				robot.logger.debug "about to parse body"
				data = JSON.parse(body)
				robot.logger.debug "about to resolve"
				resolve(
					switch fetch
						when 'games_owned'
							 data.response.games
						when 'game_info'
							data.game.gameName
						else
							'ERROR: UNKNOWN FETCH'
				)
			catch e
				robot.logger.debug "about to reject promise beacuse" + e
				reject e

module.exports = (robot) ->

	# establish semi-persistence structure
	dataStore = robot.brain.data.gametime = {
		state: {} # store the complete state of every gametime (one active per channel at any time). Includes things like users games owned (possibly duplicated across rooms and time, but that's a good thing.)
		games: {} # game info. mainly steam ID to name mappings.
		steamUserMap: {} # store this globally - user names in chat system should be unique, right?
	}

	# regardless of state, start the process in the current channel when someone issues the gametime command
	robot.respond /gametime/i, (res) ->
		curRoom = res.message.room
		dataStore.state[curRoom] = { 
			phase: "gather_players"
			users: {}
		}

		robot.logger.debug "Starting gametime in #{curRoom}. State phase set to #{dataStore.state[curRoom].phase}"
		robot.logger.debug "Full state: " + JSON.stringify(dataStore,null,2)

		res.send """
		**Time for games!**
		-----------------------------
		Say `games for me` to participate
		-OR-
		Say `games for USERNAME` to indicate another user's participation.
		-----------------------------
		Anyone can say `#{robot.name} call game vote` to start the next phase.
		Anyone can say `#{robot.name} shut it down` to extinguish the potential for games.
		"""

	robot.respond /shut it down/i, (res) ->
		curRoom = res.message.room
		dataStore.state[curRoom] = { 
			phase: "inactive"
			users: {}
		}

		robot.logger.debug "Stopping gametime in #{curRoom}. State phase set to #{dataStore.state[curRoom].phase}"
		robot.logger.debug "Full state: " + JSON.stringify(dataStore,null,2)

		res.send """
		**This gametime survey is totally cancelled**
		_much like the Space Olympics_
		"""

	robot.respond /call game vote/i, (res) ->
		curRoom = res.message.room
		dataStore.state[curRoom].phase = 'gather_votes'

		robot.logger.debug "Full state: " + JSON.stringify(dataStore,null,2)
		# get all steam info right here. cache/use stored game names. query games owned every time.
		for tmpPlayer, obj of dataStore.state[curRoom].users
			robot.logger.debug "Processing #{tmpPlayer}"
			robot.logger.debug "Fetching owned games"
			steam_api_fetch(robot,'games_owned',{steamid: dataStore.steamUserMap[tmpPlayer]})
			.then (response) ->
				robot.logger.debug "OH THE THINGS I WAS PROMISED! It's finally HAPPENING!"
				dataStore.state[curRoom].users[tmpPlayer].gamesOwned = response
				robot.logger.debug "Done fetching owned games"
			.then ->
				robot.logger.debug "THEN, on to game name lookups.."
				for g in dataStore.state[curRoom].users[tmpPlayer].gamesOwned
					robot.logger.debug "checking out #{g.appid}"
					dataStore.games[g.appid] ?= {name: ''}
					if dataStore.games[g.appid].name == ''
						robot.logger.debug "doing a lookup for #{g.appid}"
						steam_api_fetch(robot,'game_info',{appid: g.appid}).then (reponse) ->
							robot.logger.debug "OH THE THINGS I WAS PROMISED! It's finally HAPPENING! Game name: #{reponse}"
							dataStore.games[g.appid].name = reponse
							robot.logger.debug "dataStore.games[#{g.appid}].name: " + dataStore.games[g.appid].name
					else
						robot.logger.debug "not doing a lookup for #{g.appid} beause I already know it as #{dataStore.games[g.appid].name}"



	# if the current channel is gathering players, handle it
	robot.hear /games for (.*)$/i, (msg) ->
		curRoom = msg.message.room
		if dataStore.state[curRoom].phase == "gather_players"
			userToAdd = msg.match[1].toLowerCase()
			if userToAdd == "me" then userToAdd = msg.message.user.name.toLowerCase() 
			msg.send "Adding **#{userToAdd}** for games!"
			dataStore.state[curRoom].users[userToAdd] = {
				gamesOwned: {}
			}
			if not dataStore.steamUserMap[userToAdd]?
				msg.reply """
				I don't know a steam ID for **#{userToAdd}**. 
				Please reply with `steamid for #{userToAdd} is STEAMID` so that I can look up available games.
				"""
		else
			robot.logger.debug "#{curRoom}: heard #{msg.match[0]} but it's not gametime in #{curRoom}"

		robot.logger.debug "Full state: " + JSON.stringify(dataStore,null,2)

	# if a steam ID is supplied while gathering players anywhere, store it (on top of any that might exist, why not?)
	robot.hear /steamid( for )?(.*?) (is )?(\d+)/, (msg) ->
		curRoom = msg.message.room
		if dataStore.state[curRoom].phase == "gather_players"
			tmpUser = msg.match[2].toLowerCase()
			tmpSteamID = msg.match[4]
			dataStore.steamUserMap[tmpUser] = tmpSteamID
			msg.reply "Got it! Steam ID for #{tmpUser} is set to #{tmpSteamID}"
			robot.logger.debug "#{curRoom}: heard #{msg.match[0]}. Storing #{tmpUser} -> #{tmpSteamID}"
			robot.logger.debug "Full state: " + JSON.stringify(dataStore,null,2)
		else
			robot.logger.debug "#{curRoom}: heard #{msg.match[0]} but it's not gametime in #{curRoom}"