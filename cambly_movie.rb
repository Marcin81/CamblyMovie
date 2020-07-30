#!/usr/bin/env ruby

require 'json'
require 'curb'
require 'down'
require 'progressbar'
require 'thor'
require 'uri'

module Cambly
  class Menu < ::Thor
    desc 'download', 'Download your movies from Cambly to specified limit.'
    option :email, required: true, type: :string
    option :password, required: true, type: :string
    option :limit, type: :numeric, default: 1
    option :destination_dir, type: :string

    def download
      Cambly::Movie.new(options).save
    end
  end

  private

  class Movie
    def initialize(options={})
      @email = options.fetch(:email)
      @password = options.fetch(:password)
      @limit = options.fetch(:limit, 1)
      @destination_dir = options.fetch(:destination_dir, ::Dir.pwd)
    end

    def save
      begin
        login
        fetch_list
        download_list
      rescue => e
        puts "We catched the error: #{e}"
      end
    end

    private

    attr_reader :email, :password, :limit, :destination_dir
    attr_accessor :result, :video_rows

    BASE_URL = 'https://www.cambly.com'

    def session_url
      "#{BASE_URL}/api/sessions"
    end

    def login_params
      {
        email: email,
        password: password
      }
    end

    def headers
      {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/81.0.4044.138 Safari/537.36',
        "Content-Type": 'application/json; charset=UTF-8'
      }
    end

    def login
      http = Curl.post(session_url, login_params.to_json) do |curl|
        curl.headers = headers
      end
      self.result = JSON.parse(http.body_str).fetch('result')
    end

    def fetch_list
      http = Curl.get(charts_url) do |curl|
        curl.headers = list_headers
      end
      self.video_rows = JSON.parse(http.body_str).fetch('result').select{ |v| v['hasVideoUrl'] }
    end

    def download_list
      puts "Downloading #{video_rows.size} files ..."
      video_rows.each do |video_row|
        full_path = Path.new(video_row['startTime'], destination_dir).full_path
        download(video_row['videoURL'], full_path)
      end
    end

    def list_headers
      {
        'Accept' => 'application/json, text/javascript, */*; q=0.01',
        'Authorization' => "Cambly session-token='#{token}'"
      }
    end

    def token
      result['token']
    end

    def charts_url
      "#{BASE_URL}/api/chats?#{encoded_chars_url_params}"
    end

    def chars_url_params
      params = {
        language: :en,
        userId: user_id,
        sort: -1,
        role: :student
      }

      limit.to_i > 0 ? params.merge(limit: limit) : params
    end

    def encoded_chars_url_params
      URI.encode_www_form(chars_url_params)
    end

    def user_id
      result['userId']
    end

    def file_name(video_row)
      start_time(video_row).strftime('lesson_%A_%F_%H_%M.mp4')
    end

    def download(url, filename)
      Downloader.new(url, filename).download
    end
  end

  class Path
    attr_reader :start_time
    attr_reader :destination_dir

    def initialize(time_str, destination_dir = ::Dir.pwd)
      @start_time = Time.at(time_str)
      @destination_dir = destination_dir
    end

    def full_path
      prepare_path
      "#{path}/#{file_name}"
    end

    def prepare_path
      FileUtils.makedirs(path) unless Dir.exists?(path)
    end

    private

    def file_name
      start_time.strftime('lesson_%A_%F_%H%M.mp4')
    end

    def path
      "#{destination_dir}/#{year}/#{month}"
    end

    def month
      @month ||= start_time.strftime('%B')
    end

    def year
      @year ||= start_time.strftime('%Y')
    end
  end

  class Downloader
    attr_reader :url, :filename

    def initialize(url, filename)
      @url = url
      @filename = filename
    end

    def download
      ::Down.download(url, download_params.merge(destination: filename))
    end

    protected

    attr_accessor :progress_bar

    private

    def download_params
      {
        content_length_proc: content_length_proc,
        progress_proc: progress_proc
      }
    end

    def progress_proc
      -> (progress) { self.progress_bar.progress = progress }
    end

    def content_length_proc
      -> (content_length) {
        self.progress_bar = ProgressBar.create(progress_bar_params.merge(total: content_length))
      }
    end

    def progress_bar_params
      {
        title: 'Progress',
        starting_at: 0,
        format: format
      }
    end

    def format
      "\e[0;34m%t: |%B|\e[0m  %j of 100% Size: %c/%C; %e"
    end
  end
end

Cambly::Menu.start(ARGV)
