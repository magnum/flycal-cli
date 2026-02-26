# frozen_string_literal: true

require "thor"
require "time"
require "tty-prompt"
require "tty-spinner"

module FlycalCli
  class Cli < Thor
    package_name "flycal"

    def self.exit_on_failure?
      true
    end

    desc "login", "Connetti al tuo account Google"
    def login
      if Auth.logged_in?
        puts "✓ Sei già connesso al tuo account Google."
        puts "\nEsegui 'flycal calendars' per impostare il calendario di default."
        return
      end

      unless Config.credentials_exist?
        puts "Errore: File credentials non trovato."
        puts "\nPer configurare flycal:"
        puts "1. Vai su https://console.cloud.google.com/apis/credentials"
        puts "2. Crea credenziali 'Applicazione desktop' (Desktop app)"
        puts "3. Scarica il JSON e salvalo come: #{Config.credentials_path}"
        puts "\nAggiungi anche questo URI come redirect autorizzato:"
        puts "  http://127.0.0.1:9292/oauth2callback"
        return
      end

      begin
        Auth.login
        puts "\n✓ Autenticazione completata con successo!"
        puts "\nEsegui 'flycal calendars' per impostare il calendario di default."
      rescue FlycalCli::Error => e
        puts "Errore: #{e.message}"
        exit 1
      end
    end

    desc "logout", "Disconnetti dall'account Google"
    def logout
      unless Auth.logged_in?
        puts "Non sei connesso a nessun account Google."
        return
      end

      Auth.logout
      puts "✓ Disconnesso con successo."
    end

    desc "calendars", "Mostra i calendari disponibili e imposta quello di default"
    def calendars
      unless Auth.logged_in?
        puts "Non sei connesso. Esegui prima 'flycal login'."
        exit 1
      end

      creds = Auth.credentials
      service = CalendarService.new(creds)

      spinner = TTY::Spinner.new("Caricamento calendari... ", format: :dots)
      spinner.auto_spin
      calendars = service.list_calendars
      spinner.stop("✓")

      if calendars.empty?
        puts "Nessun calendario trovato."
        return
      end

      # Costruisci lista per selezione (display => calendar_id)
      default_id = Config.calendar_default
      choices = calendars.to_h do |cal|
        primary = cal.primary ? " (principale)" : ""
        default = (cal.id == default_id) ? " [default]" : ""
        summary = cal.summary || cal.id
        label = "#{summary}#{primary}#{default}"
        [label, cal.id]
      end

      prompt = TTY::Prompt.new
      selected_id = prompt.select(
        "Scegli il calendario di default:",
        choices,
        per_page: 15,
        filter: true
      )

      calendar = calendars.find { |c| c.id == selected_id }
      if calendar
        Config.calendar_default = calendar.id
        puts "\n✓ Calendario di default impostato: #{calendar.summary}"
      end
    end

    desc "search", "Cerca eventi nei calendari"
    option :calendar, type: :string, aliases: "-c", desc: "Nome o ID del calendario (default: calendario default)"
    option :from, type: :string, aliases: "-f", required: true, desc: "Data/ora inizio (es. 2025-01-01 o 2025-01-01T09:00)"
    option :to, type: :string, aliases: "-t", required: true, desc: "Data/ora fine (es. 2025-01-31 o 2025-01-31T18:00)"
    option :description, type: :string, aliases: "-d", desc: "Filtra per descrizione (testo)"
    def search
      unless Auth.logged_in?
        puts "Non sei connesso. Esegui prima 'flycal login'."
        exit 1
      end

      time_min = parse_datetime(options[:from])
      time_max = parse_datetime(options[:to], end_of_day: true)

      if time_min > time_max
        puts "Errore: la data 'from' deve essere prima della data 'to'."
        exit 1
      end

      creds = Auth.credentials
      service = CalendarService.new(creds)

      calendar_ids = resolve_calendar_ids(service, options[:calendar])
      if calendar_ids.empty?
        puts "Nessun calendario trovato."
        exit 1
      end

      events = service.list_all_events(
        calendar_ids,
        time_min: time_min,
        time_max: time_max,
        query: options[:description]
      )

      print_events(service, events)
      print_summary(events)
    end

    default_task :help

    private

    def parse_datetime(str, end_of_day: false)
      return nil if str.nil? || str.empty?

      if str.include?("T")
        Time.parse(str)
      else
        d = Date.parse(str)
        t = d.to_time
        end_of_day ? t + 86400 - 1 : t  # 23:59:59 per --to quando è solo data
      end
    end

    def resolve_calendar_ids(service, calendar_name)
      calendar_lists = service.list_calendars

      if calendar_name.nil? || calendar_name.empty?
        default_id = Config.calendar_default
        if default_id
          return [default_id]
        end
        # Usa calendario principale se disponibile
        primary = calendar_lists.find(&:primary)
        return [primary.id] if primary
        # Altrimenti primo calendario
        return [calendar_lists.first.id] if calendar_lists.any?
        return []
      end

      # Cerca per nome o ID
      matches = calendar_lists.select do |cal|
        cal.id == calendar_name ||
          (cal.summary && cal.summary.downcase.include?(calendar_name.downcase))
      end

      matches.map(&:id)
    end

    def print_events(service, events)
      # Usa lista calendari per i nomi (evita chiamate API extra)
      calendar_list = service.list_calendars
      calendar_names = calendar_list.to_h { |c| [c.id, c.summary || c.id] }

      events.each do |item|
        cal_id = item[:calendar_id]
        event = item[:event]
        cal_name = calendar_names[cal_id] || cal_id

        start_time = event.start&.date_time || event.start&.date
        end_time = event.end&.date_time || event.end&.date

        start_str = format_datetime(start_time)
        end_str = format_datetime(end_time)
        desc = event.summary || "(senza titolo)"
        desc = event.description&.slice(0, 80) if event.summary.nil? && event.description

        puts "#{cal_name} | #{start_str} | #{end_str} | #{desc}"
      end
    end

    def format_datetime(dt)
      return "-" if dt.nil?

      if dt.is_a?(String)
        dt
      else
        dt.strftime("%Y-%m-%d %H:%M")
      end
    end

    def print_summary(events)
      total_minutes = 0

      events.each do |item|
        event = item[:event]
        start = event.start&.date_time || event.start&.date
        end_dt = event.end&.date_time || event.end&.date

        next if start.nil? || end_dt.nil?

        start = start.to_time if start.respond_to?(:to_time)
        end_dt = end_dt.to_time if end_dt.respond_to?(:to_time)
        total_minutes += (end_dt - start) / 60
      end

      hours = (total_minutes / 60).floor
      mins = (total_minutes % 60).round

      puts "\n---"
      puts "Eventi trovati: #{events.size}"
      puts "Tempo totale occupato: #{hours}h #{mins}min"
    end
  end
end
