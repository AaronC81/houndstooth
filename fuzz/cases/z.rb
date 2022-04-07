
class Translator
    #: (String, String) -> String
    def translate(text, language)
        "#{text} in #{language} is..."
    end

    #!arg String
    [
        "english", "french", "german", "japanese",
        "spanish", "urdu", "korean", "hungarian",
    ].each do |lang,|
        #!arg String
        #!arg String
        define_method(:"to_#{lang}") do |s,|
            translate(s, lang)
        end
    end
end

t = Translator.new
x = t.to_german("Hello")
