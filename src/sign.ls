require! {
  'when': wn
  'child_process': { spawn }
  'debug'
}

# this function signs a data using
# bank private key and openssl
module.exports = (dataToSign, pemKeyAddress) ->
  (resolve, reject) <- wn.promise
  debug 'Payment[sign] keyFileAddress is: ' pemKeyAddress

  args = [
    "smime"
    "-sign"
    "-inkey"
    pemKeyAddress
    "-signer"
    pemKeyAddress
    "-certfile"
    pemKeyAddress
    "-noattr"
    "-nodetach"
  ]

  proc = spawn 'openssl', args, { stdio: ['pipe', 'pipe', 'pipe'] }

  result = ""
  proc.stdout.on 'data', (data) ->
    result := result + data.toString('utf8')

  proc.stdout.on 'end', (end) ->
    resolve result.split(/\r?\n\r?\n/gm)[1]

  errorData = ""
  proc.stderr.on 'data', (data) ->
    errorData := errorData + data.toString('utf8')

  proc.stderr.on 'end', (data) ->
    if errorData isnt ""
      error 'Payment[sign]: proccess stderr end:', errorData
      reject errorData

  proc.on 'error', (err) ->
    error 'Payment[sign]: proccess error:', err
    reject err

  proc.on 'uncaughtException', (uncaughtException) ->
    error 'Payment[sign]: proccess uncaughtException: ', uncaughtException 
    reject uncaughtException

  proc.stdin.end(dataToSign)
