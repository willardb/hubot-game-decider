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

module.exports = (robot) ->

	# establish semi-persistence structure
	dataStore = robot.brain.data.gametime = {
		state: {}
		games: {}
		steamUserMap: {}
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
				Please reply with `#{robot.name} steamid for #{userToAdd} is STEAMID` so that I can look up available games.
				"""
		else
			robot.logger.debug "#{curRoom}: heard #{msg.match[0]} but it's not gametime in #{curRoom}"

	### STEAM API BASICS
	robot.hear /t/i, (msg) ->
		query = { key: 'APIKEY', steamid: 'USERID', format: 'json' }
		url = 'http://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/'
		msg.robot.http(url).query(query).get() (err, res, body) ->
			data = JSON.parse(body)
			msg.send 'error?:' + err
			for g in data.response.games
				robot.logger.debug g.appid
	###