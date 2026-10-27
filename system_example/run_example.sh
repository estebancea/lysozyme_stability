#!/bin/bash
# Example workflow (system 18, replicate 1): packmol -> minimization -> equilibration -> production -> analysis
# Usage: bash run_example.sh   
# Requires: GROMACS (gmx_mpi) and Packmol (set PACKMOL=/path/to/packmol if it is not in your PATH)

module load gromacs/2022.1
module load python/intelpython3/2021.4.0

DT_FS=2                              # time step [fs]
DT_PS=0.002                          # time step [ps]
STEPS_PER_NS=$(( 1000000 / DT_FS ))  # steps per ns (500000 for 2 fs)

Ns1=500000     # Number of steps, EQ-1 NVT (2 fs)                                   [1 ns]
Ns2=2500000    # Number of steps, EQ-2 NPT (2 fs)                                   [5 ns]
Ns3=500000     # Number of steps, EQ-3 NPT (2 fs), without position restraints      [1 ns]
Ns4=100000000  # Number of steps, production NPT (2 fs), without position restraints [200 ns]

system=18      # selected example system
replicate=1    # selected replicate

BOX_NM=8.43147 # initial cubic box edge [nm] (see README.md)

PACKMOL=${PACKMOL:-packmol}

# Project root = parent directory of this script
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
PATH_PROJECT=$(pwd)

# Example topology and Packmol input
TOPOL="$PATH_PROJECT/system_example/system.top"         # selected example topology
INPUT_PACKMOL="$PATH_PROJECT/system_example/system.inp" # selected initial configuration

PATH_SYSTEM="$PATH_PROJECT/MD/system_${system}/run_${replicate}"
PATH_RESULTS="$PATH_PROJECT/results/system_${system}/run_${replicate}"
mkdir -p "$PATH_SYSTEM"
mkdir -p "$PATH_RESULTS"

# Stop with a clear message if an expected file is missing
require_file() {
    if [ ! -s "$1" ]; then
        printf "\nERROR: expected file not found: %s\n" "$1" >&2
        exit 1
    fi
}

# ----------------------------------------------------------------
# Initialization
# ----------------------------------------------------------------
printf "\n### Initialization ###\n"
mkdir -p "$PATH_SYSTEM/0_packmol"
cd "$PATH_SYSTEM/0_packmol" || exit 1

cp "$INPUT_PACKMOL" system.inp
"$PACKMOL" < system.inp >> packmol.log 2>&1
require_file system.pdb

# Packmol writes a PDB without box information: convert to GROMACS format and set the box
gmx_mpi editconf -f system.pdb -o system.gro -box $BOX_NM $BOX_NM $BOX_NM >> editconf.log 2>&1
INITIAL="$PATH_SYSTEM/0_packmol/system.gro"
require_file "$INITIAL"

# ----------------------------------------------------------------
# MINIMIZATION
# ----------------------------------------------------------------
printf "\n### Minimization ###\n"
mkdir -p "$PATH_SYSTEM/1_min"
cd "$PATH_SYSTEM/1_min" || exit 1
cp "$PATH_PROJECT/mdp/minimization.mdp" .

gmx_mpi grompp -f minimization.mdp -c "$INITIAL" -r "$INITIAL" -p "$TOPOL" -o min.tpr >> grompp.log 2>&1
gmx_mpi mdrun -deffnm min >> mdrun.log 2>&1

printf "  "
grep "Steepest Descents converged" mdrun.log
printf "  "
grep "Potential Energy" mdrun.log
printf "  "
grep "Maximum force" mdrun.log
printf "  "
grep "Norm of force" mdrun.log
printf "  \n"

mkdir pre-min
mv minimization.mdp min.* pre-min
mv *.log pre-min
require_file pre-min/min.gro
cp pre-min/min.gro .
printf "  \n"

#######  MIN-2 #######
printf "Energy Minimization - 2 \n  "
cp "$PATH_PROJECT/mdp/minimization2.mdp" .

gmx_mpi grompp -f minimization2.mdp -c pre-min/min.gro -r "$INITIAL" -p "$TOPOL" -o min.tpr >> grompp.log 2>&1
gmx_mpi mdrun -deffnm min >> mdrun.log 2>&1

printf "  "
grep "Steepest Descents converged" mdrun.log
printf "  "
grep "Potential Energy" mdrun.log
printf "  "
grep "Maximum force" mdrun.log
printf "  "
grep "Norm of force" mdrun.log
printf "  \n"
require_file min.gro

# ----------------------------------------------------------------
# EQUILIBRATION
# ----------------------------------------------------------------
mkdir -p "$PATH_SYSTEM/2_eq"
cd "$PATH_SYSTEM/2_eq" || exit 1

#######  EQ-1 #######
TIME=$(( Ns1 / STEPS_PER_NS ))
printf " Equilibration NVT using %s fs as time step for %s steps (%s ns)  \n  " "$DT_FS" "$Ns1" "$TIME"
cp "$PATH_PROJECT/mdp/equilibrationNVT.mdp" equilibration.mdp
sed -i "s/VALUE_DT/$DT_PS/" equilibration.mdp
sed -i "s/VALUE_NSTEPS/$Ns1/" equilibration.mdp

gmx_mpi grompp -f equilibration.mdp -c "$PATH_SYSTEM/1_min/min.gro" -r "$INITIAL" -p "$TOPOL" -o eq.tpr -maxwarn 10 >> grompp.log 2>&1
printf "  "
grep "This run will generate roughly" grompp.log
gmx_mpi mdrun -deffnm eq >> mdrun.log 2>&1

printf "  "
grep "                 (ns/day)    (hour/ns)" mdrun.log
printf "  "
grep "Performance:" mdrun.log
printf "  "

printf 'Pressure\nTemperature\nTotal-Energy\n' | gmx_mpi energy -f eq.edr -s eq.tpr -nbmax 10 -nbmin 10 -o "$PATH_RESULTS/eq_1.xvg" >> energy_1.log 2>&1
require_file eq.gro

mkdir eq1
mv equilibration.mdp eq.* eq1
mv *.log eq1
printf "  \n"


#######  EQ-2 #######
TIME=$(( Ns2 / STEPS_PER_NS ))
printf " Equilibration NPT using %s fs as time step for %s steps (%s ns)  \n  " "$DT_FS" "$Ns2" "$TIME"
cp "$PATH_PROJECT/mdp/equilibrationNPT.mdp" equilibration.mdp
sed -i "s/VALUE_DT/$DT_PS/" equilibration.mdp
sed -i "s/VALUE_NSTEPS/$Ns2/" equilibration.mdp

gmx_mpi grompp -f equilibration.mdp -c eq1/eq.gro -r "$INITIAL" -p "$TOPOL" -t eq1/eq.cpt -o eq.tpr -maxwarn 10 >> grompp.log 2>&1
printf "  "
grep "This run will generate roughly" grompp.log
gmx_mpi mdrun -deffnm eq >> mdrun.log 2>&1

printf "  "
grep "                 (ns/day)    (hour/ns)" mdrun.log
printf "  "
grep "Performance:" mdrun.log
printf "  "

printf 'Pressure\nDensity\nTemperature\nTotal-Energy\n' | gmx_mpi energy -f eq.edr -s eq.tpr -nbmax 10 -nbmin 10 -o "$PATH_RESULTS/eq_2.xvg" >> energy_2.log 2>&1
require_file eq.gro

mkdir eq2
mv equilibration.mdp eq.* eq2
mv *.log eq2
printf "  \n"


#######  EQ-3 #######
TIME=$(( Ns3 / STEPS_PER_NS ))
printf " Equilibration NPT, without position restraints, using %s fs as time step for %s steps (%s ns)  \n  " "$DT_FS" "$Ns3" "$TIME"
cp "$PATH_PROJECT/mdp/equilibrationNPT2.mdp" equilibration.mdp
sed -i "s/VALUE_DT/$DT_PS/" equilibration.mdp
sed -i "s/VALUE_NSTEPS/$Ns3/" equilibration.mdp

gmx_mpi grompp -f equilibration.mdp -c eq2/eq.gro -p "$TOPOL" -t eq2/eq.cpt -o eq.tpr -maxwarn 10 >> grompp.log 2>&1
printf "  "
grep "This run will generate roughly" grompp.log
gmx_mpi mdrun -deffnm eq >> mdrun.log 2>&1

printf "  "
grep "                 (ns/day)    (hour/ns)" mdrun.log
printf "  "
grep "Performance:" mdrun.log
printf "  "

printf 'Pressure\nDensity\nTemperature\nTotal-Energy\n' | gmx_mpi energy -f eq.edr -s eq.tpr -nbmax 10 -nbmin 10 -o "$PATH_RESULTS/eq_3.xvg" >> energy_3.log 2>&1
require_file eq.gro

mkdir eq3
mv equilibration.mdp eq.* eq3
mv *.log eq3
printf "  \n"


# ----------------------------------------------------------------
# PRODUCTION
# ----------------------------------------------------------------
mkdir -p "$PATH_SYSTEM/3_prod"
cd "$PATH_SYSTEM/3_prod" || exit 1

TIME=$(( Ns4 / STEPS_PER_NS ))
printf " Production NPT using %s fs as time step for %s steps (%s ns) \n  " "$DT_FS" "$Ns4" "$TIME"

cp "$PATH_PROJECT/mdp/production.mdp" .
sed -i "s/VALUE_DT/$DT_PS/" production.mdp
sed -i "s/VALUE_NSTEPS/$Ns4/" production.mdp

gmx_mpi grompp -f production.mdp -c "$PATH_SYSTEM/2_eq/eq3/eq.gro" -p "$TOPOL" -t "$PATH_SYSTEM/2_eq/eq3/eq.cpt" -o prod.tpr >> grompp.log 2>&1
printf "  "
grep "This run will generate roughly" grompp.log
gmx_mpi mdrun -deffnm prod >> mdrun.log 2>&1

printf "  "
grep "                 (ns/day)    (hour/ns)" mdrun.log
printf "  "
grep "Performance:" mdrun.log
printf "  "

printf 'Pressure\nDensity\nTemperature\nTotal-Energy\n' | gmx_mpi energy -f prod.edr -s prod.tpr -nbmax 10 -nbmin 10 -o "$PATH_RESULTS/prod.xvg" >> energy_prod.log 2>&1
require_file prod.xtc

# ----------------------------------------------------------------
# ANALYSIS
# ----------------------------------------------------------------
# Index groups below refer to GROMACS default groups: 0 = System, 1 = Protein, 4 = Backbone
cd "$PATH_SYSTEM" || exit 1
mkdir -p 4_analysis
cd 4_analysis || exit 1

# Center on the protein and make molecules whole (output: whole system)
echo 1 0 | gmx_mpi trjconv -s "$PATH_SYSTEM/3_prod/prod.tpr" -f "$PATH_SYSTEM/3_prod/prod.xtc" -o protein.xtc -pbc mol -center -ur compact >> trjconv_1.log 2>&1
# Starting structure
echo 0 0 | gmx_mpi trjconv -s "$PATH_SYSTEM/3_prod/prod.tpr" -f protein.xtc -o start.pdb -pbc mol -center -dump 0 >> trjconv_2.log 2>&1
gmx_mpi editconf -f start.pdb -o start.gro >> editconf.log 2>&1
# RMSD (backbone), radius of gyration, RMSF per residue (protein)
echo 4 4 | gmx_mpi rms -s "$PATH_SYSTEM/2_eq/eq3/eq.tpr" -f protein.xtc -tu ns -o "$PATH_RESULTS/rmsd.xvg" >> rmsd.log 2>&1
echo 1 | gmx_mpi gyrate -s "$PATH_SYSTEM/3_prod/prod.tpr" -f protein.xtc -o "$PATH_RESULTS/gyrate.xvg" >> gyrate.log 2>&1
echo 1 | gmx_mpi rmsf -s "$PATH_SYSTEM/3_prod/prod.tpr" -f protein.xtc -res -o "$PATH_RESULTS/rmsf.xvg" >> rmsf.log 2>&1
# Solvent accessible surface area: total, and hydrophobic/hydrophilic (|atom charge| <= 0.2 e)
gmx_mpi sasa -s "$PATH_SYSTEM/3_prod/prod.tpr" -f protein.xtc -b 0 -o "$PATH_RESULTS/area_SASA.xvg" -odg "$PATH_RESULTS/solv_SASA.xvg" -tu ns -surface 'protein' >> sasa.log 2>&1
gmx_mpi sasa -s "$PATH_SYSTEM/3_prod/prod.tpr" -f protein.xtc -b 0 -o "$PATH_RESULTS/area_SASA_Hydrophobic_Hydrophilic.xvg" -odg "$PATH_RESULTS/solv_SASA_Hydrophobic_Hydrophilic.xvg" -surface 'group "protein"' -output '"Hydrophobic" group "protein" and charge {-0.2 to 0.2}; "Hydrophilic" group "protein" and not charge {-0.2 to 0.2}; "Total" group "protein"' -tu ns >> sasa2.log 2>&1
