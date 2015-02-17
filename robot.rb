#!/usr/bin/env ruby

###########################################
#        FUTURESTACK 14 BADGE DEMO        #
#           (c) 2014 New Relic            #
#                                         #
# For more information, see:              #
# github.com/newrelic/futurestack14_badge #
###########################################

require 'RMagick'
require 'httparty'

WIDTH  = 264
HEIGHT = 176

BLACK = 1
WHITE = 0

# You'll want to insert your agent URL here
AGENT_URL = "https://agent.electricimp.com/REPLACEME/image"

image = Magick::Image.read("robot.png") {
  self.colorspace = Magick::GRAYColorspace
  self.image_type = Magick::BilevelType
  self.antialias = false
}.first.resize_to_fit(WIDTH, HEIGHT).extent(WIDTH, HEIGHT)

image.rotate!(180)

pixels = image.export_pixels(0, 0, WIDTH, HEIGHT, 'I')

def interlace(pixels)
  image = ""
  pixels.each_slice(WIDTH) do |row|
    binned_pixels = row.map{|x| x > 0 ? WHITE : BLACK}
    image << [binned_pixels.join].pack("B*")
  end

  return image
end

options = {
  :body => interlace(pixels)
}

HTTParty.post(AGENT_URL, options)
