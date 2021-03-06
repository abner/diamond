#!/usr/bin/env ruby
$:.unshift File.join( File.dirname( __FILE__ ), '../lib')
#
# this is an example where the arpeggiator outputs midi clock
#

require "diamond"

@output = UniMIDI::Output.gets

opts = { 
  :gate => 90,   
  :interval => 7,
  :midi => @output,
  :midi_clock_output => true,
  :pattern => Diamond::Pattern["UpDown"],
  :range => 4, 
  :rate => 8
}

arp = Diamond::Arpeggiator.new(98, opts)

chord = ["C3", "G3", "Bb3", "A4"]

arp.add(chord)
   
arp.start(:focus => true)
