#!/bin/bash
parallell="$1"
threads="$2"
program="$3"
min_freespace="1048576" # 1GB er 1048576
packages="youtube-dl curl jq screen"

##### Spørsmål om å laste ned parallellt
if [ "$parallell" != "0" ] && [ "$parallell" != "1" ]; then
    while true; do
        echo ""
        read -p "Ønsker du å laste ned parallelt [y/n/q]? (Anbefalt om du har god båndbredde på nettverket) " response_parallelt
        case $response_parallelt in
            [Yy]* ) parallell=1; break;;
            [Nn]* ) parallell=0; break;;
            [Qq]* ) exit;;
            * ) echo "Svar [y]es, [n]o eller [q]uit";;
        esac
    done
fi

##### Spørsmål om hvor mange nedlastninger skal skje samtidig, bare nødvendig om forje spørsmål var ja
if [ "$parallell" != "0" ]; then
    if [ "$threads" = "" ]; then
        while true; do
            echo ""
            read -p "Hvor mange samtidige nedlastninger skal skje? " response_threads
            case $response_threads in
                [123456789][1234567890] ) threads=$response_threads; break;;
                [23456789] ) threads=$response_threads; break;;
                * ) echo "";echo "Feil: Bruk tall fra 2 til 99";;
            esac
        done
    else
        case $threads in
            [123456789][1234567890] );;
            [23456789] );;
            * ) echo "";echo "Feil: Bruk tall fra 2 til 99"; exit;;
        esac
    fi
fi

##### Spørsmål om hvilken serie som ønskes lastet ned
if [ "$program" = "" ]; then
    while true; do
        echo "" "https://tv.nrk.no/serie/<serienavn>" ""
        read -p "Hvilken serie ønsker du å laste ned? " program

        program_check=$(curl -s "http://psapi-granitt-prod-ne.cloudapp.net/series/$program" | grep "https://tv.nrk.no/serie")
        if [ "$program_check" = "" ]; then
            echo "" "404: Finner ikke serie"
        fi
    done
else
    program_check=$(curl -s "http://psapi-granitt-prod-ne.cloudapp.net/series/$program" | grep "https://tv.nrk.no/serie")
    if [ "$program_check" = "" ]; then
        echo "" "404: Finner ikke serie"
        exit
    fi
fi

##### Opprett mappe til nedlastningen av serien
if [ ! -d "./${program}" ]; then
    mkdir "./${program}"
    if [ ! -d "./${program}" ]; then
        echo "" "Kunne ikke opprette mappe: ./${program}"
        exit
    fi
fi

cd "./${program}"

links_raw=""

##### Hent ut linker til episodene i serien
seasons=$(curl -s http://psapi-granitt-prod-ne.cloudapp.net/series/$program | jq ".seasons" | jq ".[].id" | cut -f 2 -d '"')
for season in ${seasons}
do
    season_links=$(curl -s "http://psapi-granitt-prod-ne.cloudapp.net/series/$program/seasons/$season/Episodes" | jq '.[]._links.share.href' | cut -f 2 -d '"')
    links_raw+="$season_links"
    links_raw+=$'\n'
done
links=$(echo "$links_raw" | grep "tv.nrk.no")
links_num=$(echo "$links" | wc -l)
progress="0"

##### Seriell nedlastning
if [ "$parallell" = "0" ]; then
    for link in ${links}
    do
        while true; do
            if [ "$cur_freespace" -gt "$min_freespace" ]; then
                progress=$(expr $progress + 1)
                printf "\n\n"
                echo "Starter nedlastning ($progress/$links_num)"
                youtube-dl --write-sub --sub-format ttml --convert-subtitles srt --embed-subs -o 'S%(season_number)02dE%(episode_number)02d.%(title)s.%(height)sp.WEB.DL-NoGRoUP.%(ext)s' "$link"
                break;
            else
                echo "Lite plass ledig, avventer til det er $(expr $min_freespace / 1048576)GB plass ledig, venter 30 sekunder..."
                sleep 30
            fi
        done
    done
fi

##### Parallell nedlastning
thread_num="0"
if [ "$parallell" = "1" ]; then
    for link in ${links}
    do
        while true; do
            sleep 0.5
            screen_rows=`screen -list | wc -l`
            screen_num=$(expr $screen_rows - 2)
            if [ "$screen_num" -ge "$threads" ]; then
                echo "Maximum threads ($screen_num/$threads), waiting"
                sleep 10
            else
                cur_freespace=$(df $(pwd) | tail -n 1 | awk '{ print $4 }')
                if [ "$cur_freespace" -gt "$min_freespace" ]; then
                    thread_num=$(expr $thread_num + 1)
                    screen -S "nrk-dl-$program-$thread_num" -d -m
                    sleep 0.1
                    screen -r "nrk-dl-$program-$thread_num" -X stuff "youtube-dl --write-sub --sub-format ttml --convert-subtitles srt --embed-subs -o 'S%(season_number)02dE%(episode_number)02d.%(height)sp.WEB.DL-NoGRoUP.%(ext)s' "$link""
                    sleep 0.1
                    screen -r "nrk-dl-$program-$thread_num" -X stuff '\n'
                    sleep 0.1
                    screen -r "nrk-dl-$program-$thread_num" -X stuff "exit"
                    sleep 0.1
                    screen -r "nrk-dl-$program-$thread_num" -X stuff '\n'
                    progress=$(expr $progress + 1)
                    echo "Startet nedlastning ($progress/$links_num)"
                    sleep 1
                    break;
                else
                    echo "Lite plass ledig, avventer til det er $(expr $min_freespace / 1048576)GB plass ledig, venter 30 sekunder..."
                    sleep 30
                fi
            fi
        done
    done
    echo "" "Alle nedlastninger har startet, de kjører i bakgrunnen; sjekk dem ved å bruke (screen -list)"
fi
