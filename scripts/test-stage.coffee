# Description:
#   teststage workflow
#
# Dependencies:
#
#
# Configuration:
#
#
# Commands:
#
# Notes:
#
# Author:
#   craigrigdon

mat_room = process.env.HUBOT_MATTERMOST_CHANNEL
apikey = process.env.HUBOT_OCPAPIKEY
domain = process.env.HUBOT_OCPDOMAIN
devApiTestTemplate = process.env.HUBOT_DEV_APITEST_TEMPLATE
testApiTestTemplate = process.env.HUBOT_TEST_APITEST_TEMPLATE
ocTestNamespace = process.env.HUBOT_TEST_NAMESPACE # TODO: need to define this else where


#---------------Supporting Functions-------------------

getTimeStamp = ->
  date = new Date()
  timeStamp = date.getFullYear() + "/" + (date.getMonth() + 1) + "/" + date.getDate() + " " + date.getHours() + ":" +  date.getMinutes() + ":" + date.getSeconds()
  RE_findSingleDigits = /\b(\d)\b/g
  # Places a `0` in front of single digit numbers.
  timeStamp = timeStamp.replace( RE_findSingleDigits, "0$1" )

#----------------Robot-------------------------------

module.exports = (robot) ->

  robot.on "test-stage", (obj) ->
    # expecting the following from obj

    # repoFullName # repo name from github payload
    # eventStage # stage object from memory to update
    # envKey # enviromnet key from github action param

    console.log "object passed is  : #{JSON.stringify(obj)}"

    #----------------API TEST----------------------

    # lets get template path and set deploy uid.. i dont like the feel of this.
    # TODO: if running manualy as responder we will have to get the current deploy uid
    switch obj.envKey
      when "dev"
       templateUrl = devApiTestTemplate
      when 'test'
       templateUrl = testApiTestTemplate
      else
       console.log "failed to set templateURL"
       return

    #TODO: err check args and exit , let chat room know
    console.log "Test against environment #{obj.envKey}"

    # get job template from repo
    robot.http(templateUrl)
      .header('Accept', 'application/json')
      .get() (err, httpres, body) ->

        # check for errs
        if err
          console.log "Encountered an error :( #{err}"
          return

        fs = require('fs')
        yaml = require('js-yaml')

        data = yaml.load(body)
        jsonString = JSON.stringify(data)
        jsonParsed = JSON.parse(jsonString)
        # get job object from template
        # TODO: check if kind is of job type
        job = jsonParsed.objects[0]
        console.log job

        #add env var with ID of deployment for tracking
        data =  {"name": "DEPLOY_UID","value": obj.eventStage.deploy_uid}
        console.log "#{JSON.stringify(data)}"
        console.log "add new data to job yaml"
        job.spec.template.spec.containers[0].env.push data
        console.log "#{JSON.stringify(job)}#"

        # send job to ocp api jobs endpoint in test frame work namespace
        robot.http("https://#{domain}/apis/batch/v1/namespaces/#{ocTestNamespace}/jobs")
         .header('Accept', 'application/json')
         .header('Authorization', "Bearer #{apikey}")
         .post(JSON.stringify(job)) (err, httpRes, body2) ->
          # check for errs
          if err
            console.log "Encountered an error sending job to ocp :( #{err}"
            return

          data = JSON.parse body2
          console.log "returning ocp jobs response"
          console.log data

          # check for ocp returned status responses.
          if data.kind == "Status"
            status = data.status
            reason = data.message
            mesg "#{status} #{reason}"
            mesg = "Failed to Start API Test #{status} #{reason}"
            console.log mesg

            # update brain
            event = robot.brain.get(obj.repoFullName)
            event.entry.push mesg
            obj.eventStage.test_status = "failed"

            # send message to chat
            robot.messageRoom mat_room, "#{mesg}"

          else if data.kind == "Job"
            kind = data.kind
            buildName = data.metadata.name
            namespace = data.metadata.namespace
            time = data.metadata.creationTimestamp

            mesg = "Starting #{kind} #{buildName} in #{namespace} at #{time}"
            console.log mesg

            # update brain
            event = robot.brain.get(obj.repoFullName)
            event.entry.push mesg
            obj.eventStage.test_status = "pending"

            # send message to chat
            robot.messageRoom mat_room, "#{mesg}"

            #hubot will now wait for test results recieved from another defined route in hubot.


