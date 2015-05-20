require 'json'
require 'pp'
require 'yaml'

require 'sinatra'

set :bind, '0.0.0.0'
set :port, 9944

def _get(*args, &blk) get(*args, &blk) ; end
def _post(*args, &blk) get(*args, &blk) ; end

PERSISTENT_FILE = "eduke.yml"

class User
  attr_accessor :email, :first_name, :last_name, :phone
  def initialize(email, fn, ln, phone)
    @email = email
    @first_name = fn
    @last_name = ln
    @phone = phone
  end

  def as_hash
    hash = {}
    self.instance_variables.each do |var|
      sym = var[1..-1].to_sym
      hash[sym] = self.instance_variable_get var
    end
    hash
  end

  def to_json(*args)
    as_hash.to_json
  end
end

trap('INT') do
  File.open(PERSISTENT_FILE, 'w+') do |f|
    f.write(YAML.dump($users))
  end
end

if File.exists?(PERSISTENT_FILE)
  $users = YAML.load_file(PERSISTENT_FILE)
else
  $users = []
end

_get '/' do
  urls = File.open(__FILE__).readlines
    .grep(/^(?:get|post|delete|put)/)
    .map {|e| e.chop.sub(/'(?= )[^#]+#?/, "' ")}
    .map {|e| "<li><a href='#{e.gsub(/.*'(.*)'.*/, '\1')}'>#{e.gsub(/'(?= ).*/, '')}</a>#{e.gsub(/.*'(?= )/, ' -- ')}</li>"}
    .join("\n")

  return html_response <<-eod
  <h1>Educational HTTP server welcomes you!</h1>
  <h2>Purposes</h2>
  <div>
    The server is intended to provide simple REST API and Web interface for people
      who is studying software testing automation.
  </div>
  <h2>URLS</h2>
  <div>Brief list of routes</div>
  <ul>#{urls}</ul>
eod
end

get '/web/home' do # Web UI home page
  return html_response <<-eod
    <h1>Hi!</h1>
    <a href='/web/adduser'>add user</a>
    <a href='/web/listusers'>list users</a>
    <a href='/web/about'>about</a>
eod
end

get '/web/adduser' do # Web interface to add user (does not add actually, just form)
  return html_response <<-eod
    <h1>#{request.path_info}</h1>
    <form method='post' action='/users/add2'>
      <table>
        <tr><th>email</th><td><input name='email' type='text'/></td></tr>
        <tr><th>First Name:</th><td><input name='firstName' type='text'/></td></tr>
        <tr><th>Last Name:</th><td><input name='lastName' type='text'/></td></tr>
      </table>
      <input type='submit'/>
    </form>
eod
end

get '/web/listusers' do # Web page with table of all users
  user_lines = ""
  $users.each do |u|
    user_lines += "<tr><td>#{u.email}</td><td>#{u.first_name}</td><td>#{u.last_name}</td></tr>\n"
  end
  return html_response <<-eod
    <h1>#{request.path_info}</h1>
    <table>
      <tr><th>email</th><th>First Name</th><th>Last Name</th></tr>
      #{user_lines}
    </table>
eod
end

get '/web/about' do # Web about page
  return html_response <<-eod
    <script>
      var tc1 = "Back to Home page";
      var tc2 = "Press me if you can";
      function btnClicked(){
        var div1 = document.getElementById("div1");
        div1.textContent = "Wow! You have clicked me!";
      }
      function btnMouseOver(){
        var btn1 = document.getElementById("btn1");
        btn1.value = tc2;
        btn1.disabled = true;
      }
      function versionOnMouseOver(){
        var btn1 = document.getElementById("btn1");
        btn1.disabled = false;
        btn1.value = tc1;
      }
    </script>
    <h1>#{request.path_info}</h1>
    <div id='div1'>Expected text: Simplest App to test from Cucumber</div>
    <div id='version' onmouseover='versionOnMouseOver()'>Version 1.0</div>
    <input id='btn1' type='button' onclick='btnClicked()' value='Back to Home page' onmouseover='btnMouseOver()'>
eod
end

get '/math/plus' do # REST Math operation plus for two arguments: /math/plus?a=1&b=2
  headers \
    'content-type' => 'application/json;charset=utf-8'
  begin
    a = params[:a].to_i
    b = params[:b].to_i
    json_response(result: a+b)
  rescue => exc
    status 422
    return json_error("something went wrong: #{exc}")
  end
end

get '/math/divide' do # REST Math operation divide for two arguments: /math/divide?a=9&b=4
  headers \
    'content-type' => 'application/json;charset=utf-8'
  begin
    a = params[:a].to_f
    b = params[:b].to_f
    json_response(result: a/b)
  rescue => exc
    status 422
    return json_error("something went wrong: #{exc}")
  end
end

get '/users' do # REST service to list specified user (/users?email=a@b.c) or all users
  headers \
    'content-type' => 'application/json;charset=utf-8'
  email = params[:email]
  if email.nil?
    status 200
    return json_response(users: $users)
  else
    if !user_exists?(email)
      status 404
      return json_error("User with '#{email}' not found")
    else
      status 200
      return json_response(user: get_user(email))
    end
  end
end

delete '/users' do # REST service to delete specified user (/users?email=a@b.c) or all users
  headers \
     'content-type' => 'application/json;charset=utf-8'
  email = params[:email]
  if email.nil?
    status 200
    $users = []
    return json_response(users: $users)
  else
    if !user_exists?(email)
      status 404
      return json_error("User with '#{email}' not found")
    else
      delete_user(email)
      status 200
      return json_response(users: $users)
    end
  end
end

post '/users/edit' do # REST service to update details of specified user (/users/edit?email=)
  headers \
     'content-type' => 'application/json;charset=utf-8'
  email = params[:email]
  if email.nil?
    status 422
    return json_error("Required parameter 'email' is missed")
  else
    if !user_exists?(email)
      status 404
      return json_error("User with '#{email}' not found")
    else
      data = JSON.parse request.body.read
      if data.nil?
        return json_error("Empty request body",
                          %Q^Expected someting like {"email":"user11@email.com", "firstName":"autotest", "lastName":"user"}^)
      end
      STDERR.puts "BODY: #{data}"
      first_name = data['firstName']
      last_name = data['lastName']
      phone = data['phone']
      user = get_user(email)
      user.first_name = first_name
      user.last_name = last_name
      user.phone = phone
      status 200
      return json_response(users: $users, edited_user: user)
    end
  end
end

post '/users/add2' do # REST service UNUSED now
  STDERR.puts params[:email]
end

post '/users/add' do # REST service to add new user
  headers \
    'content-type' => 'application/json;charset=utf-8'
  data = JSON.parse request.body.read
  STDERR.puts "BODY: #{data}"
  first_name = data['firstName']
  last_name = data['lastName']
  email = data['email']
  phone = data['phone']
  required = [first_name, last_name, email]
  if required.include?(nil)
    # bad error example
    return json_error("Required parameter should not be nil")
  else
    if user_exists?(email)
      return json_error("User with email: #{email} already exists")
    else
      status 201
      user = add_user(email, last_name, first_name, phone)
      return json_response(users: $users, new_user: user)
    end
  end
end

_get '*' do
  headers \
    'content-type' => 'application/json;charset=utf-8'
  status 422
  return json_error("unknown route: #{request.url}")
end

_post '*' do
  headers \
    'content-type' => 'application/json;charset=utf-8'
  status 422
  return json_error("unknown route: #{request.url}")
end


private

def add_user(email, last_name, first_name, phone)
  user = User.new email, last_name, first_name, phone
  $users << user
  return user
end

def get_user(email)
  $users.select{|u| u.email == email}[0]
end

def delete_user(email)
  $users.delete_if{|u| u.email == email}
end

def user_exists?(email)
   !get_user(email).nil?
end

def json_response(hsh)
  JSON.dump hsh
end

def json_error(msg, usage=nil)
  h = {}
  h[:error] = msg
  h[:usage] = usage unless usage.nil?
  return h.to_json
end

def html_response(body)
  return "<html><body>\n#{body}</body></html>"
end

