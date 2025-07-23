import from mtllm { Model }

glob llm = Model(model_name="gpt-4o-mini");

node Equipment {}

walker FitnessAgent {
    has gear: dict = {};
    
    can start with `root entry {
        visit [-->(`?Equipment)];
    }
}

node Weights(Equipment) {
    has available: bool = True;
    
    can check with FitnessAgent entry {
        visitor.gear["weights"] = self.available;
    }
}

node Cardio(Equipment) {
    has machine: str = "treadmill";
    
    can check with FitnessAgent entry {
        visitor.gear["cardio"] = self.machine;
    }
}

"""Create a personalized workout plan based on available equipment and space."""
def create_workout(gear: dict) -> str by llm(incl_info=(gear));

node Trainer {
    can plan with FitnessAgent entry {
        visitor.gear["workout"] = create_workout(visitor.gear);
    }
}

walker CoachWalker(FitnessAgent) {
    can get_plan with `root entry {
        visit [-->(`?Trainer)];
    }
}

with entry {
    root ++> Weights();
    root ++> Cardio();
    root ++> Trainer();
    
    agent = CoachWalker() spawn root;
    print("Your Workout Plan:");
    print(agent.gear['workout']);
}