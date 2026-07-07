# Fixing Port Authority airport wait time scrapers

### User

LGA / JFK / EWR (Port Authority airports)

Let's see how we can fix these.

Grab the link from each script. If it doesn't work navigate up to the main URL and then navigate to find the wait times. Find the elements of the new wait time section for each airport, and individual compare each one to its relevant script to see what scraping changes need to be made for each of the three airports.

Once you have done this provide proposed changes and or scripts to update these three airports.

---

### Assistant

Let me start by reading the three scripts carefully, then fetching each airport's website.

---

### User

I need you to go back to the data transformation step in all three scripts (LGA, JFK, EWR) and if the results object has a wait time of "No Wait", for standard or pre-check, then that should be transformed to a 0, not an NA. My existing code that I originally imported for this project has that logic so if No wait = 0, any numerical value = that value, else NA

---

### Assistant

Let me re-read all three files I just produced to make the surgical change.

---

### User

Please remove LGA, JFK, and EWR airport authority scripts from the Readme TODO list, they are complete

---

### Assistant

The README only has two lines — there's no TODO list in it. The TODO list lives in my memory of the project, not in the file itself.

Before I add anything, I want to confirm with you: do you want me to build out the README with a proper TODO section (and mark LGA/JFK/EWR as done or simply omit them), or did you mean to update a different file — like the Script Descriptions `.md` or a notes doc?

---

### User

Please review the entire project. In one of the recent chats you created a new readme.md file that has a todo list in it.

---

### Assistant

Found it — the README was created in the chat titled "Airport wait times data source investigation". Let me fetch that file.

---

### User

please update the readme document attached here and remove the DEN script bug

---

### Assistant

There's your `TODO.md`. Once you download it, commit it to GitHub, and upload it to this Claude project, I'll be reading the live version at the start of every chat going forward. Also worth updating the memory note — let me do that now.

---

### User

uploaded as todo_list.txt to files. I am ending this chat now

---

### Assistant

Got it — I can see `todo_list.txt` is already in the project files. Let me update memory to reflect the correct filename.

---

### Assistant

TSA Wait Time Shiny App

---

