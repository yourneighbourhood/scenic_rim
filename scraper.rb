require 'scraperwiki'
require 'mechanize'

starting_url = "http://pdonline.scenicrim.qld.gov.au/Modules/Applicationmaster/default.aspx?page=found&1=thisweek&4a=COM.Bd',%20'COM.Bn',%20'COM.Ip','pbeDevComp','DevEnf','MC.Bd1',%20'MC.Bd2',%20'MC.Bn',%20'MC.I','RL.Bd1','RL.Bd2','RL.Bn','RL.IP','OW.Bd1','OW.Bd2','OW.Bn','OW.Ip','Subdiv&6=F"
comment_url = 'mailto:mail@scenicrim.qld.gov.au'

def clean_whitespace(a)
  a.gsub("\r", ' ').gsub("\n", ' ').squeeze(" ").strip
end

def scrape_table(doc, comment_url)
  doc.search('table tbody tr').each do |tr|
    # Columns in table
    # Show  Number  Submitted  Details
    tds = tr.search('td')

    # Yes, this is "where no records"[sic]
    break if tds[0].inner_text =~ /There where no records/

    h = tds.map{|td| td.inner_html}
  
    info_url = 'http://pdonline.scenicrim.qld.gov.au/Modules/Applicationmaster/' + tds[0].at('a')['href'].strip
    info_page = @agent.get(info_url)

    record = {
      'info_url' => info_url,
      'comment_url' => comment_url,
      'council_reference' => clean_whitespace(h[1]),
      'date_received' => Date.strptime(clean_whitespace(h[2]), '%d/%m/%Y').to_s,
      # TODO: Some DAs have multiple addresses, we're just getting the first :(
      'address' => clean_whitespace(info_page.at('div#lblProp').at('a').inner_text.strip) + ", QLD",
      'description' => CGI::unescapeHTML(info_page.at('div#lblDetails').inner_html.split('<br>')[0].split('Description: ')[1].strip),
      'date_scraped' => Date.today.to_s
    }
    if ScraperWiki.select("* from data where `council_reference`='#{record['council_reference']}'").empty? 
      ScraperWiki.save_sqlite(['council_reference'], record)
    else
      puts "Skipping already saved record " + record['council_reference']
    end
  end
end

def scrape_and_follow_next_link(doc, comment_url)
  scrape_table(doc, comment_url)
  nextButton = doc.at('.rgPageNext')
  unless nextButton.nil? || nextButton['onclick'] =~ /return false/
    form = doc.forms.first
    
    # The joy of dealing with ASP.NET
    form['__EVENTTARGET'] = nextButton['name']
    form['__EVENTARGUMENT'] = ''
    # It doesn't seem to work without these stupid values being set.
    # Would be good to figure out where precisely in the javascript these values are coming from.
    form['ctl00%24RadScriptManager1']=
      'ctl00%24cphContent%24ctl00%24ctl00%24cphContent%24ctl00%24Radajaxpanel2Panel%7Cctl00%24cphContent%24ctl00%24ctl00%24RadGrid1%24ctl00%24ctl03%24ctl01%24ctl10'
    form['ctl00_RadScriptManager1_HiddenField']=
      '%3B%3BSystem.Web.Extensions%2C%20Version%3D3.5.0.0%2C%20Culture%3Dneutral%2C%20PublicKeyToken%3D31bf3856ad364e35%3Aen-US%3A0d787d5c-3903-4814-ad72-296cea810318%3Aea597d4b%3Ab25378d2%3BTelerik.Web.UI%2C%20Version%3D2009.1.527.35%2C%20Culture%3Dneutral%2C%20PublicKeyToken%3D121fae78165ba3d4%3Aen-US%3A1e3fef00-f492-4ed8-96ce-6371bc241e1c%3A16e4e7cd%3Af7645509%3A24ee1bba%3Ae330518b%3A1e771326%3Ac8618e41%3A4cacbc31%3A8e6f0d33%3Aed16cbdc%3A58366029%3Aaa288e2d'
    doc = form.submit(form.button_with(:name => nextButton['name']))
    scrape_and_follow_next_link(doc, comment_url)
  end
end

@agent = Mechanize.new

# Jump through bollocks agree screen
doc = @agent.get(starting_url)
doc = doc.forms.first.submit(doc.forms.first.button_with(:value => "Agree"))
doc = @agent.get(starting_url)

scrape_and_follow_next_link(doc, comment_url)
