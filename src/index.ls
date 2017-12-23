require! {
  'easysoap'
  'debug'
  './sign'
}

module.exports = class Gateway
  (config) ->
    @username = config.username
    @password = config.password
    @pemKeyAddress = config.pemKeyAddress

    params =
      host: 'pna.shaparak.ir'
      path: '/ref-payment2/jax/merchantService?wsdl'
      wsdl: '/ref-payment2/jax/merchantService?wsdl'

    @soapClient = easysoap.createClient params, { secure: yes }

  _login: ->
    query =
      method: 'MerchantLogin'
      params:
        param:
          UserName: @username
          Password: @password

    @soapClient.call query
    .then (result) ~>
      if result?.data?.MerchantLoginResponse?.return?.0?.Result is "erSucceed"
        sessionId = result.data.MerchantLoginResponse.return.1.SessionId
        wsContext =
          SessionId: sessionId
          UserId: @username
          Password: @password

        wsContext
      else
        wn.reject do
          reason: "Payment[Login]: Bad response from bank's while logging-in"
          response: result?.data?.MerchantLoginResponse?.return?.0?.Result

    .catch (err) ~>
      wn.reject do
        message: "Payment[Login]: Cannot login to bank using `MerchantLogin` method"
        err: err

  _getCertificate: (wsContext, invoiceNumber, amount, returnPage, mobile, email) ->
    query =
      method: 'GenerateTransactionDataToSign'
      params:
        param:
          ReserveNum: invoiceNumber
          Amount: amount
          AmountSpecified: yes
          RedirectUrl: returnPage
          TransType: \enGoods
          WSContext: wsContext

    debug 'Payment[getCertificate]: calling GenerateTransactionDataToSign with params: ', query.params.param
      
    if mobile?
      query.params.param.MobileNo = mobile
    if email?
      query.params.param.Email = email

    @soapClient.call query
    .then (result) ->
      if result?.data?.GenerateTransactionDataToSignResponse?.return?.0?.Result is "erSucceed"
        dataToSign = result.data.GenerateTransactionDataToSignResponse.return.1.DataToSign
        uniqueId = result.data.GenerateTransactionDataToSignResponse.return.2.UniqueId
        return { dataToSign, uniqueId }
      else
        reason = "Payment[getCertificate]: Bad response from bank's TransactionDataToSign API"
        wn.reject do
          reason: reason
          response: result?.data?.GenerateTransactionDataToSignResponse?.return?.Result

    .catch (err) ->
      message = "Payment[getCertificate]: Calling GenerateTransactionDataToSign failed"
      wn.reject do
        message: message
        err: err

  _getToken: (wsContext, UniqueId, Signature) ->
    query =
      method: 'GenerateSignedDataToken'
      params: param: { UniqueId, Signature: Signature, WSContext: wsContext }

    @soapClient.call query
    .then (result) ->
      if result?.data?.GenerateSignedDataTokenResponse?.return?.0?.Result is "erSucceed"
        expirationDate = result.data.GenerateSignedDataTokenResponse.return.1.ExpirationDate
        token = result.data.GenerateSignedDataTokenResponse.return.2.Token
        return { expirationDate, token }
      else
        wn.reject do
          reason: "Payment[getToken]: Bad response from bank's GenerateSignedDataToken API"
          response: result?.data?.GenerateSignedDataTokenResponse?.return?.Result

    .catch (err) ->
      wn.reject do
        message: "Payment[getToken]: Calling GenerateSignedDataToken failed"
        err: err

  _verifyPayment: (wsContext, Token, RefNum) ->
    query =
      method: 'VerifyMerchantTrans'
      params:
        param: { RefNum, Token, WSContext: wsContext }

    @soapClient.call query
    .then (result) ->
      if result?.data?.VerifyMerchantTransResponse?.return?.0?.Result is "erSucceed"
        amount = result.data.VerifyMerchantTransResponse.return.1.Amount
        referenceNumber = result.data.VerifyMerchantTransResponse.return.2.RefNum
        return { amount, referenceNumber }
      else
        wn.reject do
          message: "Payment[getToken]: Bad response from bank's VerifyMerchantTrans API"
          response: result?.data?.VerifyMerchantTransResponse?.return?.Result

    .catch (err) ->
      wn.reject do
        message: "Payment[getToken]: Calling VerifyMerchantTrans failed"
        err: err

  # mobile and email parameters are optional for now
  requestPaymentToken: (amount, invoiceNumber, returnPage, mobile, email) ->
    # Login to the bank via soapClient
    wsContext <~ @_login!.then
    debug 'Payment[requestToken]: login was successfull'
    # Get transaction data to sign from bank
    { uniqueId, dataToSign } <~ @_getCertificate(wsContext, invoiceNumber, amount, returnPage, mobile, email).then
    debug 'Payment[requestToken]: getting certificate was successfull'
    # Sign tranaction data with our payment key
    signature <~ sign(dataToSign, @pemKeyAddress).then
    debug 'Payment[requestToken]: signing token was successfull'
    # Get transaction token
    @_getToken wsContext, uniqueId, signature

  recievePay: (token, refNumber) ->
    # Login to the bank via soapClient
    wsContext <~ @_login!.then
    # Completely verify payment and fully receive the money
    @_verifyPayment wsContext, token, refNumber
