
digit = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]


digit.each{ |f|
  digit.each{ |s|
    digit.each{ |t|
      puts [f,s,t].join(",")
    }
  }
}
