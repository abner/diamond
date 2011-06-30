#!/usr/bin/env ruby
module Diamond
  
  class Arpeggiator
    
    include MIDIEmitter
    include MIDIReceiver
    include Syncable
    
    extend Forwardable
    
    DefaultChannel = 0
    DefaultVelocity = 100
    
    attr_reader :clock,
                :sequence
                
    attr_accessor :channel
    
    def_delegators :clock, :join, :start
                         
    #
    # a numeric tempo rate (BPM), or unimidi input is required by the constructor.  in the case that you use a MIDI input, it will be used as a clock source
    #
    # the constructor also accepts a number of options
    #       
    # * <b>channel</b>: restrict input messages to the given MIDI channel. will operate on all input sources
    #
    # * <b>gate</b>: <em>gate</em> refers to how long the arpeggiated notes will be held out. the <em>gate</em> value is a percentage based on the rate.  if the rate is 4, then a gate of 100 is equal to a quarter note. the default <em>gate</em> is 75. <em>Gate</em> must be positive and less than 500
    #
    # * <b>interval</b>: the arpeggiator increments the <em>pattern</em> over <em>interval</em> scale degrees <em>range</em> times.  the default <em>interval</em> is 12, meaning one octave above the current note. <em>interval</em> may be any positive or negative number
    #  
    # * <b>midi</b>: this can be a unimidi input or output. will accept a single device or an array
    #
    # * <b>pattern_offset</b>: <em>pattern_offset</em> n means that the arpeggiator will begin on the nth note of the sequence (but not omit any notes). the default <em>pattern_offset</em> is 0.
    # 
    # * <b>pattern</b>: A Pattern object that computes the contour of the arpeggiated melody
    #    
    # * <b>range</b>: the arpeggiator increments the <em>pattern</em> over <em>interval</em> scale degrees <em>range</em> times. <em>range</em> must be 0 or greater. the default <em>range</em> is 3
    #
    # * <b>rate</b>: <em>rate</em> is how fast the arpeggios will be played. the default is 8, which is an eighth note. rate may be 0 (whole note) or greater but must be equal to or less than <em>resolution</em>
    #  
    # * <b>resolution</b>: the resolution of the arpeggiator (numeric notation)    
    #    
    def initialize(tempo_or_input, options = {}, &block)
      @mute = false      
      @actions = { :tick => nil }
      
      @channel = options[:channel]      
      resolution = options[:resolution] || 128
      
      @clock = ClockStack.new(tempo_or_input, resolution, options)
      
      initialize_midi_io(options[:midi]) unless options[:midi].nil?
      initialize_syncable(options)
      
      @sequence = ArpeggiatorSequence.new(resolution, options)

      bind_events(&block)
    end
    
    def method_missing(method, *args, &block)
      @sequence.respond_to?(method) ? @sequence.send(method, *args, &block) : super
    end
    
    # add input notes. takes a single note or an array of notes
    def add(notes, options = {})
      notes = [notes].flatten
      notes = sanitize_input_notes(notes, MIDIMessage::NoteOn, options)
      @sequence.add(notes)
    end
    
    # remove input notes. takes a single note or an array of notes
    def remove(notes, options = {})
      notes = [notes].flatten
      notes = sanitize_input_notes(notes, MIDIMessage::NoteOff, options)
      @sequence.remove(notes)
    end
    
    # toggle mute on this arpeggiator
    def toggle_mute
      muted? ? unmute : mute
    end
    
    # mute this arpeggiator
    def mute
      @mute = true
      emit_pending_note_offs
    end
    
    # unmute this arpeggiator
    def unmute
      @mute = false
    end
    
    # is this arpeggiator muted?
    def muted?
      @mute
    end
    
    # stops the clock and sends any remaining MIDI note-off messages that are in the queue
    def stop
      @clock.stop
      emit_pending_note_offs             
    end
    
    private
    
    def sanitize_input_notes(notes, klass, options)
      channel = options[:channel] || DefaultChannel
      velocity = options[:velocity] || DefaultVelocity
      notes.map do |note|
        note = note.kind_of?(String) ? klass[note].new(channel, velocity) : note
        (@channel.nil? || note.channel == @channel) ? note : nil 
      end.compact
    end
    
    def update_clock
      @clock.update_destinations(@midi_destinations)
      @clock.ensure_tick_action(self, &@actions[:tick]) unless @actions[:tick].nil?
    end
    alias_method :on_midi_destinations_updated, :update_clock
    alias_method :on_sync_updated, :update_clock
            
    def initialize_midi_io(devices)
      devices = [devices].flatten
      emit_midi_to(devices.find_all { |d| d.type == :output }.compact)
      receive_midi_from(devices.find_all { |d| d.type == :input }.compact)      
    end
    
    def initialize_midi_source_listener(source)
      listener = MIDIEye::Listener.new(source)
      listener.listen_for(:class => MIDIMessage::NoteOn) { |event| add(event[:message]) }
      listener.listen_for(:class => MIDIMessage::NoteOff) { |event| remove(event[:message]) }
      listener.start(:background => true)
      listener
    end
    
    def bind_events(&block)
      @actions[:tick] = Proc.new do
        @sequence.with_next do |msgs|
          unless muted?
            data = msgs.map { |msg| msg.to_bytes }.flatten
            emit_midi(data) if emit_midi? && !data.empty?
            yield(msgs) unless block.nil?
          end
        end
      end
      update_clock       
    end
  
  end
  
end
