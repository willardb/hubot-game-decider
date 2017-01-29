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

is_sane_game = (g) ->
	if (g is null) or (g == undefined) or (g == '') or /(ValveTest|Untitled)App.*/.test(g)
		return false
	else
		return true

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
				robot.logger.debug "about to reject promise because" + e
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
		res.send "Calculating common games..."
		curRoom = res.message.room
		dataStore.state[curRoom].phase = 'gather_votes'

		robot.logger.debug "Fetching owned games for all players..."
		robot.logger.debug "Full state: " + JSON.stringify(dataStore,null,2)
		# get all steam info right here. cache/use stored game names. query games owned every time.
		tmpPlayerList = []
		tmpFetchTasks = []
		robot.logger.debug "About to start builiding API fetch tasks for owned games"
		for tmpPlayer, obj of dataStore.state[curRoom].users
			robot.logger.debug "Building API fetch for #{tmpPlayer}"
			tmpPlayerList.push tmpPlayer
			tmpFetchTasks.push steam_api_fetch(robot,'games_owned',{steamid: dataStore.steamUserMap[tmpPlayer]})
		robot.logger.debug "Done builiding API fetch tasks for owned games"

		Promise.all(tmpFetchTasks).then (values) ->
			robot.logger.debug "Promise eval: all api fetch tasks are done."
			commonGames = []
			robot.logger.debug "Building list of common games..."
			for tmpPlayer, index in tmpPlayerList
				robot.logger.debug "Examining games for #{tmpPlayer}: values[#{index}] #{values[index]}"
				dataStore.state[curRoom].users[tmpPlayer].gamesOwned = values[index]
				robot.logger.debug "About to filter.."
				commonGames = if (commonGames.length == 0) then (g.appid for g in values[index]) else commonGames.filter( (value) ->
					return (g.appid for g in values[index]).indexOf(value) > -1
				)
				robot.logger.debug "Done filtering."
				robot.logger.debug "Done examining games for #{tmpPlayer}"
				robot.logger.debug "commonGames: " + JSON.stringify(commonGames)
				robot.logger.debug "values[index]: " + JSON.stringify(values[index])
			
			tmpGameList = []
			tmpNameLookupTasks = []
			for g in commonGames
				robot.logger.debug "common game appid: #{g}"
				dataStore.games[g] ?= {name: ''}
				if dataStore.games[g].name == ''
					tmpGameList.push g
					tmpNameLookupTasks.push steam_api_fetch(robot,'game_info',{appid: g})

			Promise.all(tmpNameLookupTasks).then (values) ->
				robot.logger.debug "game name values: " + JSON.stringify(values)
				for tmpGameAppid, index in tmpGameList
					dataStore.games[tmpGameAppid].name = values[index]
				robot.logger.debug "dataStore.games: " + JSON.stringify(dataStore.games)

				saneCommonGames = (g for g in commonGames when is_sane_game(dataStore.games[g].name))
				robot.logger.debug "saneCommonGames: " + JSON.stringify(saneCommonGames)
				gameListMessage = ""
				for tmpGameID,index in saneCommonGames
					robot.logger.debug "sane game: #{dataStore.games[tmpGameID].name}"
					gameListMessage += "#{index} : #{dataStore.games[tmpGameID].name}\n"
				res.send """
				*Okay, the results are IN! Here are the games we can play:*
				#{gameListMessage}
				-----------------------------
				Please send me a DM (or type in this channel) a comma separated list of numbers to indicate the games you would be willing to play.
				"""


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