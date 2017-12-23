console.log(__dirname + '/lib/');

module.exports = {
  entry: './src/index.ls',
  output: {
    filename: 'index.js',
    path: __dirname + '/lib/'
  },
  module: {
    loaders: [{
        test: /\.ls$/,
        exclude: /node_modules/,
        loader: 'livescript-loader'
    }]
  },
  devtool: "source-map"
}